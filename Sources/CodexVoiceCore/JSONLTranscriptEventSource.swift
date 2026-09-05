import Foundation

public enum CodexTranscriptStartPosition: Sendable {
  case beginning
  case end
}

public final class JSONLTranscriptEventSource {
  private final class FileCursor {
    let url: URL
    var fileIdentifier: String
    var offset: UInt64
    var pending = Data()
    var discardingOversizedLine = false
    var normalizer = JSONLTranscriptNormalizer()

    init(url: URL, fileIdentifier: String, offset: UInt64 = 0) {
      self.url = url
      self.fileIdentifier = fileIdentifier
      self.offset = offset
    }

    func reset(fileIdentifier: String) {
      self.fileIdentifier = fileIdentifier
      offset = 0
      pending.removeAll(keepingCapacity: true)
      discardingOversizedLine = false
      normalizer = JSONLTranscriptNormalizer()
    }
  }

  private let sessionsRoot: URL
  private let startPosition: CodexTranscriptStartPosition
  private let maximumTrackedFiles: Int
  private let includedThreadIDs: Set<String>?
  private let bootstrapTailBytes: Int
  private let maximumReadBytesPerFile: Int
  private let maximumLineBytes: Int
  private let includeRecentHistory: Bool
  private let fileManager: FileManager
  private var cursors: [URL: FileCursor] = [:]
  private var isPrimed = false
  private var previousPollDate = Date()
  private var observationBeganAt = Date()
  private var recentHistory: [CodexSourceEvent] = []
  private var seenFileIdentifiers = BoundedIdentitySet()
  public private(set) var lastPollReadByteCount = 0

  public init(
    sessionsRoot: URL,
    startPosition: CodexTranscriptStartPosition = .end,
    maximumTrackedFiles: Int = 64,
    includedThreadIDs: Set<String>? = nil,
    bootstrapTailBytes: Int = 2 * 1_024 * 1_024,
    maximumReadBytesPerFile: Int = 256 * 1_024,
    maximumLineBytes: Int = 2 * 1_024 * 1_024,
    includeRecentHistory: Bool = false,
    fileManager: FileManager = .default
  ) {
    self.sessionsRoot = sessionsRoot.standardizedFileURL
    self.startPosition = startPosition
    self.maximumTrackedFiles = max(1, maximumTrackedFiles)
    self.includedThreadIDs = includedThreadIDs?.isEmpty == false ? includedThreadIDs : nil
    self.bootstrapTailBytes = max(64 * 1_024, bootstrapTailBytes)
    self.maximumReadBytesPerFile = max(1_024, maximumReadBytesPerFile)
    self.maximumLineBytes = max(1_024, maximumLineBytes)
    self.includeRecentHistory = includeRecentHistory
    self.fileManager = fileManager
  }

  public func prime() throws {
    guard !isPrimed else { return }
    previousPollDate = Date()
    observationBeganAt = previousPollDate
    let files = try discoverFiles()
    for file in files {
      // A task can be archived between discovery and opening its journal.
      guard let metadata = try? fileMetadata(file) else { continue }
      seenFileIdentifiers.insert(metadata.identifier)
      let cursor = FileCursor(url: file, fileIdentifier: metadata.identifier)
      cursors[file] = cursor
      if startPosition == .end {
        _ = bootstrapAtEnd(cursor: cursor, fileSize: metadata.size)
      }
    }
    isPrimed = true
  }

  public func poll() throws -> CodexEventBatch {
    if !isPrimed { try prime() }
    let liveSince = previousPollDate
    previousPollDate = Date()
    lastPollReadByteCount = 0

    let files = try discoverFiles()
    let currentFiles = Set(files)
    cursors = cursors.filter { currentFiles.contains($0.key) }

    var batch = CodexEventBatch()
    for file in files {
      let metadata: (identifier: String, size: UInt64, createdAt: Date)
      do { metadata = try fileMetadata(file) } catch {
        cursors[file] = nil
        batch.diagnostics.append(
          CodexIngestionDiagnostic(
            file: file.path,
            message: "Journal déplacé ou indisponible : \(error.localizedDescription)"))
        continue
      }
      let cursor: FileCursor
      if let existing = cursors[file] {
        cursor = existing
        if existing.fileIdentifier != metadata.identifier || metadata.size < existing.offset {
          seenFileIdentifiers.insert(metadata.identifier)
          existing.reset(fileIdentifier: metadata.identifier)
          if startPosition == .end {
            let result = bootstrapAtEnd(cursor: existing, fileSize: metadata.size)
            batch.diagnostics.append(contentsOf: result.diagnostics)
            continue
          }
        }
      } else {
        cursor = FileCursor(url: file, fileIdentifier: metadata.identifier)
        cursors[file] = cursor
        if startPosition == .end {
          // Re-entering the recent-file window must not read the whole journal.
          // Only timestamped events written since the previous poll are live;
          // the bounded tail remains available as silent history.
          let firstObservation = seenFileIdentifiers.insert(metadata.identifier).inserted
          let earliestLiveDate =
            firstObservation && metadata.createdAt >= observationBeganAt
            ? observationBeganAt : liveSince
          let result = bootstrapAtEnd(
            cursor: cursor, fileSize: metadata.size, liveSince: earliestLiveDate)
          batch.events.append(contentsOf: result.events)
          batch.diagnostics.append(contentsOf: result.diagnostics)
          continue
        }
      }

      let result = read(cursor: cursor, emitEvents: true)
      batch.events.append(contentsOf: result.events)
      batch.diagnostics.append(contentsOf: result.diagnostics)
    }
    batch.events = batch.events.enumerated().sorted { lhs, rhs in
      switch (lhs.element.timestamp, rhs.element.timestamp) {
      case (let left?, let right?) where left != right:
        return left < right
      case (nil, _?):
        return false
      case (_?, nil):
        return true
      default:
        return lhs.offset < rhs.offset
      }
    }.map(\.element)
    return batch
  }

  /// Historical observations are deliberately separate from poll's live events.
  public func takeRecentHistory() -> [CodexSourceEvent] {
    defer { recentHistory.removeAll(keepingCapacity: true) }
    // Oldest first keeps the bounded history's most-recent tasks when several
    // journals are bootstrapped at startup (discovery itself is newest-first).
    return recentHistory.enumerated().sorted {
      let left = $0.element.timestamp ?? .distantPast
      let right = $1.element.timestamp ?? .distantPast
      return left == right ? $0.offset < $1.offset : left < right
    }.map(\.element)
  }

  private func discoverFiles() throws -> [URL] {
    guard
      let enumerator = fileManager.enumerator(
        at: sessionsRoot,
        includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
        options: [.skipsHiddenFiles]
      )
    else {
      throw CocoaError(.fileReadNoSuchFile)
    }

    var files: [(url: URL, modifiedAt: Date)] = []
    for case let url as URL in enumerator where url.pathExtension == "jsonl" {
      if let includedThreadIDs,
        !includedThreadIDs.contains(where: {
          url.deletingPathExtension().lastPathComponent.hasSuffix($0)
        })
      {
        continue
      }
      let values = try? url.resourceValues(forKeys: [
        .contentModificationDateKey, .isRegularFileKey,
      ])
      guard values?.isRegularFile == true else { continue }
      files.append((url.standardizedFileURL, values?.contentModificationDate ?? .distantPast))
    }

    return
      files
      .sorted {
        if $0.modifiedAt != $1.modifiedAt { return $0.modifiedAt > $1.modifiedAt }
        return $0.url.path > $1.url.path
      }
      .prefix(maximumTrackedFiles)
      .map(\.url)
  }

  private func fileMetadata(_ url: URL) throws -> (
    identifier: String, size: UInt64, createdAt: Date
  ) {
    let attributes = try fileManager.attributesOfItem(atPath: url.path)
    let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
    let device = (attributes[.systemNumber] as? NSNumber)?.uint64Value ?? 0
    let inode = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0
    return ("\(device):\(inode)", size, attributes[.creationDate] as? Date ?? .distantPast)
  }

  private func read(cursor: FileCursor, emitEvents: Bool) -> CodexEventBatch {
    do {
      let handle = try FileHandle(forReadingFrom: cursor.url)
      defer { try? handle.close() }
      try handle.seek(toOffset: cursor.offset)
      let data = try handle.read(upToCount: maximumReadBytesPerFile) ?? Data()
      lastPollReadByteCount += data.count
      cursor.offset += UInt64(data.count)
      return consume(data, cursor: cursor, emitEvents: emitEvents)
    } catch {
      return CodexEventBatch(
        diagnostics: [
          CodexIngestionDiagnostic(file: cursor.url.path, message: error.localizedDescription)
        ]
      )
    }
  }

  private func bootstrapAtEnd(
    cursor: FileCursor, fileSize: UInt64, liveSince: Date? = nil
  ) -> CodexEventBatch {
    do {
      let handle = try FileHandle(forReadingFrom: cursor.url)
      defer { try? handle.close() }

      let headerData = try handle.read(upToCount: 64 * 1_024) ?? Data()
      lastPollReadByteCount += headerData.count
      var headerEvents: [CodexSourceEvent] = []
      if let newline = headerData.firstIndex(of: 0x0A) {
        var header = Data(headerData[..<newline])
        if header.last == 0x0D { header.removeLast() }
        if !header.isEmpty { headerEvents = cursor.normalizer.normalize(line: header).events }
      }
      if includeRecentHistory {
        recentHistory.append(
          contentsOf: headerEvents.map {
            CodexSourceEvent(
              timestamp: $0.timestamp, origin: .transcriptHistory,
              authority: $0.authority, payload: $0.payload)
          })
      }

      let tailSize = min(UInt64(bootstrapTailBytes), fileSize)
      let tailStart = fileSize - tailSize
      try handle.seek(toOffset: tailStart)
      var tail = try handle.read(upToCount: Int(tailSize)) ?? Data()
      lastPollReadByteCount += tail.count
      if tailStart > 0 {
        guard let firstNewline = tail.firstIndex(of: 0x0A) else {
          cursor.offset = fileSize
          cursor.discardingOversizedLine = true
          return CodexEventBatch()
        }
        tail.removeSubrange(...firstNewline)
      }

      cursor.pending.removeAll(keepingCapacity: true)
      let result = consume(tail, cursor: cursor, emitEvents: true)
      // read(upToCount:) is bounded by the size snapshot, even if Codex appends
      // concurrently. Only advance across bytes actually read.
      cursor.offset = tailStart + UInt64(tail.count)
      if tailStart > 0 {
        // The discarded partial first line was also consumed from the file.
        cursor.offset = try handle.offset()
      }
      let live = result.events.filter { event in
        guard let liveSince, let timestamp = event.timestamp else { return false }
        return timestamp >= liveSince
      }
      if includeRecentHistory {
        let liveKeys = Set(live.map(\.identityKey))
        recentHistory.append(
          contentsOf: result.events
            .filter { !liveKeys.contains($0.identityKey) }
            .map {
              CodexSourceEvent(
                timestamp: $0.timestamp, origin: .transcriptHistory,
                authority: $0.authority, payload: $0.payload)
            })
      }
      return CodexEventBatch(events: live, diagnostics: result.diagnostics)
    } catch {
      cursor.offset = fileSize
      return CodexEventBatch(
        diagnostics: [
          CodexIngestionDiagnostic(file: cursor.url.path, message: error.localizedDescription)
        ]
      )
    }
  }

  private func consume(
    _ data: Data,
    cursor: FileCursor,
    emitEvents: Bool
  ) -> CodexEventBatch {
    var batch = CodexEventBatch()
    var data = data
    if cursor.discardingOversizedLine {
      guard let newline = data.firstIndex(of: 0x0A) else { return batch }
      data = Data(data[data.index(after: newline)...])
      cursor.discardingOversizedLine = false
    }
    let alreadyScanned = cursor.pending.count
    cursor.pending.append(data)
    // Walk forward once, then compact once; never rescan/copy the remaining
    // multi-megabyte buffer for every individual line.
    var start = cursor.pending.startIndex
    for newline in cursor.pending.indices.dropFirst(alreadyScanned)
    where cursor.pending[newline] == 0x0A {
      defer { start = cursor.pending.index(after: newline) }
      guard newline - start <= maximumLineBytes else {
        batch.diagnostics.append(
          CodexIngestionDiagnostic(
            file: cursor.url.path,
            message: "Ligne JSONL trop volumineuse ignorée."))
        continue
      }
      var line = Data(cursor.pending[start..<newline])
      if line.last == 0x0D { line.removeLast() }
      guard !line.isEmpty else { continue }
      let normalized = cursor.normalizer.normalize(line: line)
      if emitEvents { batch.events.append(contentsOf: normalized.events) }
      batch.diagnostics.append(
        contentsOf: normalized.diagnostics.map {
          CodexIngestionDiagnostic(file: cursor.url.path, message: $0.message)
        })
    }
    cursor.pending = Data(cursor.pending[start...])
    if cursor.pending.count > maximumLineBytes {
      cursor.pending.removeAll(keepingCapacity: false)
      cursor.discardingOversizedLine = true
      batch.diagnostics.append(
        CodexIngestionDiagnostic(
          file: cursor.url.path,
          message: "Ligne JSONL trop volumineuse ignorée."))
    }
    return batch
  }
}
