import Foundation
import XCTest

@testable import CodexVoiceCore

final class SessionIndexThreadEventSourceTests: XCTestCase {
  func testPublishesNewAndRenamedTaskTitlesWithoutRepeatingUnchangedState() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("session_index.jsonl")
    try writeLines(
      [
        ["id": "thread-a", "thread_name": "Première tâche"],
        ["id": "thread-b"],
      ],
      to: file
    )
    let source = SessionIndexThreadEventSource(fileURL: file)

    let first = source.poll()
    XCTAssertEqual(first.events.compactMap(\.threadTitle), ["Première tâche"])
    XCTAssertTrue(source.poll().events.isEmpty)

    try writeLines(
      [
        ["id": "thread-a", "thread_name": "Première tâche"],
        ["id": "thread-a", "thread_name": "Tâche renommée"],
      ],
      to: file
    )
    let renamed = source.poll()
    XCTAssertEqual(renamed.events.compactMap(\.threadTitle), ["Tâche renommée"])
  }
}

private extension CodexSourceEvent {
  var threadTitle: String? {
    guard case .threadObserved(let metadata) = payload else { return nil }
    return metadata.title
  }
}

private func writeLines(_ values: [[String: String]], to file: URL) throws {
  let lines = try values.map {
    String(decoding: try JSONSerialization.data(withJSONObject: $0), as: UTF8.self)
  }
  try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: file)
}
