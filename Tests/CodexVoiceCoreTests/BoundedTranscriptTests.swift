import Foundation
import XCTest

@testable import CodexVoiceCore

final class BoundedTranscriptTests: XCTestCase {
  func testOversizedPartialTailStillExposesTheObservedTaskWithoutSpeech() throws {
    let root = try directory()
    defer { try? FileManager.default.removeItem(at: root) }
    var bytes = try record(["type": "session_meta", "payload": ["id": "long-task"]])
    bytes.append(Data(repeating: 65, count: 3 * 1_024 * 1_024))
    try bytes.write(to: root.appendingPathComponent("long.jsonl"))
    let source = JSONLTranscriptEventSource(sessionsRoot: root, includeRecentHistory: true)
    try source.prime()
    XCTAssertTrue(try source.poll().events.isEmpty)
    let history = source.takeRecentHistory()
    XCTAssertTrue(history.contains { $0.payload.threadID == "long-task" })
    XCTAssertTrue(history.allSatisfy { $0.origin == .transcriptHistory })
  }

  func testManySmallLinesAcrossReadBoundariesStayOrderedAndUnique() throws {
    let root = try directory()
    defer { try? FileManager.default.removeItem(at: root) }
    var bytes = try record(["type": "session_meta", "payload": ["id": "A"]])
    for index in 0..<1_000 { bytes.append(try message(thread: "A", id: "item-\(index)")) }
    try bytes.write(to: root.appendingPathComponent("many.jsonl"))
    let source = JSONLTranscriptEventSource(
      sessionsRoot: root, startPosition: .beginning,
      maximumReadBytesPerFile: 8_192)
    var items: [String] = []
    for _ in 0...((bytes.count / 8_192) + 1) {
      let batch = try source.poll()
      XCTAssertTrue(batch.diagnostics.isEmpty)
      XCTAssertLessThanOrEqual(source.lastPollReadByteCount, 8_192)
      items += batch.events.compactMap {
        if case .assistantMessageCompleted(let message) = $0.payload { return message.itemID }
        return nil
      }
    }
    XCTAssertEqual(items, (0..<1_000).map { "item-\($0)" })
  }

  func testReturningOldFileBootstrapsSilentlyInsteadOfReplaying() throws {
    let root = try directory()
    defer { try? FileManager.default.removeItem(at: root) }
    let old = root.appendingPathComponent("old.jsonl")
    let other = root.appendingPathComponent("other.jsonl")
    try transcript(thread: "old").write(to: old)
    try FileManager.default.setAttributes(
      [.modificationDate: Date(timeIntervalSince1970: 10)],
      ofItemAtPath: old.path)
    try transcript(thread: "other").write(to: other)
    let source = JSONLTranscriptEventSource(
      sessionsRoot: root, maximumTrackedFiles: 1,
      bootstrapTailBytes: 65_536, includeRecentHistory: true)
    try source.prime()
    _ = source.takeRecentHistory()
    // This formerly untracked file is now recent, but all of its content is old.
    try FileManager.default.setAttributes(
      [.modificationDate: Date().addingTimeInterval(1)],
      ofItemAtPath: old.path)
    XCTAssertTrue(try source.poll().events.isEmpty)
    XCTAssertLessThanOrEqual(source.lastPollReadByteCount, 2 * 65_536)
    let history = source.takeRecentHistory()
    XCTAssertTrue(history.contains { $0.payload.threadID == "old" })
    XCTAssertTrue(history.allSatisfy { $0.origin == .transcriptHistory })
    let router = VoiceOrchestrator()
    XCTAssertTrue(router.process(CompositeCodexEventSource().ingest(history)).isEmpty)
    XCTAssertNil(router.mainConversation)
    XCTAssertTrue(source.takeRecentHistory().isEmpty)
  }

  func testIncrementalReadIsBoundedAndRecoversAfterOversizedLine() throws {
    let root = try directory()
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("test.jsonl")
    var bytes = try record(["type": "session_meta", "payload": ["id": "A"]])
    bytes.append(Data(repeating: 65, count: 10_000))
    bytes.append(10)
    bytes.append(
      try record(["type": "event_msg", "payload": ["type": "task_started", "turn_id": "turn"]]))
    bytes.append(try message(thread: "A", id: "next"))
    try bytes.write(to: file)
    let source = JSONLTranscriptEventSource(
      sessionsRoot: root, startPosition: .beginning,
      maximumReadBytesPerFile: 1_024, maximumLineBytes: 2_048)
    var events: [CodexSourceEvent] = []
    var diagnostics = 0
    for _ in 0..<16 {
      let batch = try source.poll()
      XCTAssertLessThanOrEqual(source.lastPollReadByteCount, 1_024)
      events += batch.events
      diagnostics += batch.diagnostics.count
    }
    XCTAssertEqual(
      events.filter {
        if case .assistantMessageCompleted = $0.payload { return true }
        return false
      }.count, 1)
    XCTAssertEqual(diagnostics, 1)
  }

  func testNewlyCreatedFileKeepsNewTimestampedEventsLive() throws {
    let root = try directory()
    defer { try? FileManager.default.removeItem(at: root) }
    let source = JSONLTranscriptEventSource(sessionsRoot: root, includeRecentHistory: true)
    try source.prime()
    // Future timestamp avoids filesystem/formatter clock precision in this test.
    let now = ISO8601DateFormatter().string(from: Date().addingTimeInterval(2))
    var bytes = try record(["timestamp": now, "type": "session_meta", "payload": ["id": "new"]])
    bytes.append(
      try record([
        "timestamp": now, "type": "event_msg",
        "payload": ["type": "task_started", "turn_id": "turn"],
      ]))
    bytes.append(try message(thread: "new", id: "new-message", timestamp: now))
    try bytes.write(to: root.appendingPathComponent("new.jsonl"))
    let batch = try source.poll()
    XCTAssertTrue(
      batch.events.contains {
        if case .assistantMessageCompleted = $0.payload { return true }
        return false
      })
    XCTAssertFalse(batch.events.contains { $0.origin == .transcriptHistory })
    XCTAssertTrue(try source.poll().events.isEmpty)
  }

  private func directory() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
  }

  private func transcript(thread: String) throws -> Data {
    var data = try record(["type": "session_meta", "payload": ["id": thread]])
    for _ in 0..<1_500 {
      data.append(
        try record([
          "type": "event_msg",
          "payload": ["type": "ignored", "padding": String(repeating: "x", count: 256)],
        ]))
    }
    data.append(
      try record(["type": "event_msg", "payload": ["type": "task_started", "turn_id": "turn"]]))
    data.append(try message(thread: thread, id: "historical"))
    return data
  }

  private func message(thread: String, id: String, timestamp: String = "2020-01-01T00:00:00Z")
    throws -> Data
  {
    try record([
      "timestamp": timestamp, "type": "event_msg",
      "payload": [
        "type": "item_completed", "turn_id": "turn",
        "item": [
          "id": id, "type": "AgentMessage", "phase": "final_answer", "text": "Réponse de test.",
        ],
      ],
    ])
  }

  private func record(_ object: [String: Any]) throws -> Data {
    try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) + Data([10])
  }
}
