import Foundation

public final class SessionIndexThreadEventSource {
  private let fileURL: URL
  private let maximumBytes: Int
  private var lastContents: Data?
  private var knownTitles: [String: String] = [:]

  public init(fileURL: URL, maximumBytes: Int = 5 * 1_024 * 1_024) {
    self.fileURL = fileURL
    self.maximumBytes = maximumBytes
  }

  public func poll() -> CodexEventBatch {
    let values: URLResourceValues
    do {
      values = try fileURL.resourceValues(forKeys: [.fileSizeKey])
    } catch let error as CocoaError where error.code == .fileNoSuchFile {
      return CodexEventBatch()
    } catch {
      return diagnostic("Index des tâches illisible : \(error.localizedDescription)")
    }

    guard let size = values.fileSize, size <= maximumBytes else {
      return diagnostic("Index des tâches trop volumineux.")
    }

    let data: Data
    do {
      data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
    } catch {
      return diagnostic("Index des tâches illisible : \(error.localizedDescription)")
    }
    guard data != lastContents else { return CodexEventBatch() }

    var latestTitles: [String: (title: String, timestamp: Date?)] = [:]
    var diagnostics: [CodexIngestionDiagnostic] = []
    for (offset, rawLine) in data.split(separator: 0x0A).enumerated() {
      do {
        guard
          let object = try JSONSerialization.jsonObject(with: Data(rawLine)) as? JSONObject,
          let threadID = jsonString(object["id"]),
          let title = jsonString(object["thread_name"])?
            .trimmingCharacters(in: .whitespacesAndNewlines),
          !threadID.isEmpty,
          !title.isEmpty
        else { continue }
        latestTitles[threadID] = (title, parseCodexTimestamp(object["updated_at"]))
      } catch {
        diagnostics.append(
          CodexIngestionDiagnostic(
            file: fileURL.path,
            message: "Ligne \(offset + 1) de l'index des tâches invalide."
          )
        )
      }
    }

    var events: [CodexSourceEvent] = []
    for (threadID, entry) in latestTitles where knownTitles[threadID] != entry.title {
      events.append(
        CodexSourceEvent(
          timestamp: entry.timestamp,
          origin: .sessionIndex,
          authority: .sessionIndex,
          payload: .threadObserved(
            CodexThreadMetadata(threadID: threadID, title: entry.title, isSubagent: false)
          )
        )
      )
      knownTitles[threadID] = entry.title
    }
    lastContents = data
    return CodexEventBatch(events: events, diagnostics: diagnostics)
  }

  private func diagnostic(_ message: String) -> CodexEventBatch {
    CodexEventBatch(
      diagnostics: [CodexIngestionDiagnostic(file: fileURL.path, message: message)]
    )
  }
}
