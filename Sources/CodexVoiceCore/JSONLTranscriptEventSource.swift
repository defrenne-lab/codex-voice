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
      normalizer = JSONLTranscriptNormalizer()
    }
  }

  private let sessionsRoot: URL
  private let startPosition: CodexTranscriptStartPosition
  private let maximumTrackedFiles: Int
  private let includedThreadIDs: Set<String>?
  private let bootstrapTailBytes: Int
  private let fileManager: FileManager
  private var cursors: [URL: FileCursor] = [:]
  private var isPrimed = false

  public init(
    sessionsRoot: URL,
    startPosition: CodexTranscriptStartPosition = .end,
    maximumTrackedFiles: Int = 64,
    includedThreadIDs: Set<String>? = nil,
    bootstrapTailBytes: Int = 2 * 1_024 * 1_024,
    fileManager: FileManager = .default
  ) {
    self.sessionsRoot = sessionsRoot.standardizedFileURL
    self.startPosition = startPosition
    self.maximumTrackedFiles = max(1, maximumTrackedFiles)
    self.includedThreadIDs = includedThreadIDs?.isEmpty == false ? includedThreadIDs : nil
    self.bootstrapTailBytes = max(64 * 1_024, bootstrapTailBytes)
    self.fileManager = fileManager
  }

  public func prime() throws {
    guard !isPrimed else { return }
    let files = try discoverFiles()
    for file in files {
      let metadata = try fileMetadata(file)
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

    let files = try discoverFiles()
    let currentFiles = Set(files)
    cursors = cursors.filter { currentFiles.contains($0.key) }

    var batch = CodexEventBatch()
    for file in files {
      let metadata = try fileMetadata(file)
      let cursor: FileCursor
      if let existing = cursors[file] {
        cursor = existing
        if existing.fileIdentifier != metadata.identifier || metadata.size < existing.offset {
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

  private func fileMetadata(_ url: URL) throws -> (identifier: String, size: UInt64) {
    let attributes = try fileManager.attributesOfItem(atPath: url.path)
    let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
    let device = (attributes[.systemNumber] as? NSNumber)?.uint64Value ?? 0
    let inode = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0
    return ("\(device):\(inode)", size)
  }

  private func read(cursor: FileCursor, emitEvents: Bool) -> CodexEventBatch {
    do {
      let handle = try FileHandle(forReadingFrom: cursor.url)
      defer { try? handle.close() }
      try handle.seek(toOffset: cursor.offset)
      let data = try handle.readToEnd() ?? Data()
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

  private func bootstrapAtEnd(cursor: FileCursor, fileSize: UInt64) -> CodexEventBatch {
    do {
      let handle = try FileHandle(forReadingFrom: cursor.url)
      defer { try? handle.close() }

      let headerData = try handle.read(upToCount: 1_024 * 1_024) ?? Data()
      if let newline = headerData.firstIndex(of: 0x0A) {
        var header = Data(headerData[..<newline])
        if header.last == 0x0D { header.removeLast() }
        if !header.isEmpty { _ = cursor.normalizer.normalize(line: header) }
      }

      let tailSize = min(UInt64(bootstrapTailBytes), fileSize)
      let tailStart = fileSize - tailSize
      try handle.seek(toOffset: tailStart)
      var tail = try handle.readToEnd() ?? Data()
      if tailStart > 0 {
        guard let firstNewline = tail.firstIndex(of: 0x0A) else {
          cursor.offset = fileSize
          return CodexEventBatch()
        }
        tail.removeSubrange(...firstNewline)
      }

      cursor.pending.removeAll(keepingCapacity: true)
      let result = consume(tail, cursor: cursor, emitEvents: false)
      cursor.offset = fileSize
      return result
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
    cursor.pending.append(data)
    while let newline = cursor.pending.firstIndex(of: 0x0A) {
      var line = Data(cursor.pending[..<newline])
      cursor.pending.removeSubrange(...newline)
      if line.last == 0x0D { line.removeLast() }
      guard !line.isEmpty else { continue }
      let normalized = cursor.normalizer.normalize(line: line)
      if emitEvents { batch.events.append(contentsOf: normalized.events) }
      batch.diagnostics.append(
        contentsOf: normalized.diagnostics.map {
          CodexIngestionDiagnostic(file: cursor.url.path, message: $0.message)
        })
    }
    return batch
  }
}
