import Foundation
import XCTest

@testable import CodexVoiceCore

final class CodexVoiceCoreTests: XCTestCase {
  func testCurrentJSONLShapeIsNormalizedAndDuplicateRepresentationIsAbsorbed() throws {
    let normalizer = JSONLTranscriptNormalizer()
    _ = normalizer.normalize(
      line: try jsonLine([
        "type": "session_meta",
        "payload": ["id": "thread-1", "thread_source": "user"],
      ]))
    _ = normalizer.normalize(
      line: try jsonLine([
        "type": "event_msg",
        "payload": ["type": "task_started", "turn_id": "turn-1"],
      ]))

    let completed = normalizer.normalize(
      line: try jsonLine([
        "type": "event_msg",
        "payload": [
          "type": "item_completed",
          "turn_id": "turn-1",
          "item": [
            "id": "message-1",
            "type": "AgentMessage",
            "phase": "commentary",
            "content": [["type": "Text", "text": "Je vérifie."]],
          ],
        ],
      ]))
    let responseItem = normalizer.normalize(
      line: try jsonLine([
        "type": "response_item",
        "payload": [
          "id": "message-1",
          "type": "message",
          "role": "assistant",
          "phase": "commentary",
          "content": [["type": "output_text", "text": "Je vérifie."]],
        ],
      ]))

    let composite = CompositeCodexEventSource()
    let first = try XCTUnwrap(composite.ingest(completed.events).first)
    let duplicate = try XCTUnwrap(composite.ingest(responseItem.events).first)
    XCTAssertEqual(first.disposition, .inserted)
    XCTAssertTrue(first.isNewTimelineEvent)
    XCTAssertEqual(duplicate.disposition, .duplicate)
    XCTAssertFalse(duplicate.isNewTimelineEvent)

    guard case .assistantMessageCompleted(let message) = first.event.payload else {
      return XCTFail("Message assistant attendu")
    }
    XCTAssertEqual(message.threadID, "thread-1")
    XCTAssertEqual(message.turnID, "turn-1")
    XCTAssertEqual(message.itemID, "message-1")
    XCTAssertEqual(message.phase, .commentary)
    XCTAssertEqual(message.text, "Je vérifie.")
  }

  func testAppServerSnapshotUpgradesJSONLEventWithoutCreatingASecondTimelineEntry() throws {
    let composite = CompositeCodexEventSource()
    let live = CodexSourceEvent(
      timestamp: nil,
      origin: .jsonlCompletedItem,
      authority: .jsonlCompleted,
      payload: .assistantMessageCompleted(
        CodexAssistantMessage(
          threadID: "thread-1",
          turnID: "turn-1",
          itemID: "message-1",
          phase: .finalAnswer,
          text: "Terminé."
        )
      )
    )
    XCTAssertEqual(composite.ingest(live).disposition, .inserted)

    let data = try JSONSerialization.data(withJSONObject: [
      "thread": [
        "id": "thread-1",
        "name": "Améliorer la fusion des threads",
        "turns": [
          [
            "id": "turn-1",
            "status": "completed",
            "items": [
              [
                "id": "message-1",
                "type": "agentMessage",
                "phase": "final_answer",
                "text": "Terminé.",
              ]
            ],
          ]
        ],
      ]
    ])
    let snapshot = AppServerSnapshotEventSource().normalize(threadReadData: data)
    let results = composite.ingest(snapshot.events)
    let messageResult = try XCTUnwrap(
      results.first {
        if case .assistantMessageCompleted = $0.event.payload { return true }
        return false
      })
    XCTAssertEqual(messageResult.disposition, .upgraded)
    XCTAssertFalse(messageResult.isNewTimelineEvent)
    XCTAssertEqual(messageResult.event.origin, .appServerSnapshot)

    let metadata = try XCTUnwrap(
      snapshot.events.first {
        if case .threadObserved = $0.payload { return true }
        return false
      })
    guard case .threadObserved(let thread) = metadata.payload else { return }
    XCTAssertEqual(thread.title, "Améliorer la fusion des threads")
  }

  func testPartialLineIsHeldUntilNewlineArrives() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let file = fixture.root.appendingPathComponent("session.jsonl")
    let prefix = try lines([
      ["type": "session_meta", "payload": ["id": "thread-1", "thread_source": "user"]],
      ["type": "event_msg", "payload": ["type": "task_started", "turn_id": "turn-1"]],
    ])
    let message = try jsonLine([
      "type": "event_msg",
      "payload": [
        "type": "item_completed",
        "turn_id": "turn-1",
        "item": [
          "id": "message-1", "type": "AgentMessage", "phase": "commentary",
          "content": [["type": "Text", "text": "En cours."]],
        ],
      ],
    ])
    var initial = prefix
    initial.append(message.prefix(message.count / 2))
    try initial.write(to: file)

    let source = JSONLTranscriptEventSource(
      sessionsRoot: fixture.root,
      startPosition: .beginning,
      maximumTrackedFiles: 1
    )
    try source.prime()
    let first = try source.poll()
    XCTAssertEqual(first.events.filter(\.isAssistantMessage).count, 0)

    try append(Data(message.dropFirst(message.count / 2)) + Data([0x0A]), to: file)
    let second = try source.poll()
    XCTAssertEqual(second.events.filter(\.isAssistantMessage).count, 1)
    XCTAssertTrue(second.diagnostics.isEmpty)
  }

  func testStartAtEndDoesNotReplayHistoryButKeepsTurnContext() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let file = fixture.root.appendingPathComponent("session.jsonl")
    try lines([
      ["type": "session_meta", "payload": ["id": "thread-1", "thread_source": "user"]],
      ["type": "event_msg", "payload": ["type": "task_started", "turn_id": "turn-1"]],
    ]).write(to: file)

    let source = JSONLTranscriptEventSource(
      sessionsRoot: fixture.root,
      startPosition: .end,
      maximumTrackedFiles: 1
    )
    try source.prime()
    XCTAssertTrue(try source.poll().events.isEmpty)

    try append(
      try lines([
        [
          "type": "response_item",
          "payload": [
            "id": "message-1", "type": "message", "role": "assistant",
            "phase": "commentary",
            "content": [["type": "output_text", "text": "Nouveau."]],
          ],
        ]
      ]), to: file)
    let batch = try source.poll()
    let event = try XCTUnwrap(batch.events.first)
    guard case .assistantMessageCompleted(let message) = event.payload else {
      return XCTFail("Message assistant attendu")
    }
    XCTAssertEqual(message.turnID, "turn-1")
  }

  func testStartAtEndRecoversCurrentTurnFromTailOfLargeTranscript() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let file = fixture.root.appendingPathComponent("session.jsonl")

    var content = try lines([
      ["type": "session_meta", "payload": ["id": "thread-large", "thread_source": "user"]]
    ])
    let padding =
      try jsonLine([
        "type": "event_msg",
        "payload": ["type": "token_count", "padding": String(repeating: "x", count: 1_024)],
      ]) + Data([0x0A])
    for _ in 0..<128 { content.append(padding) }
    content.append(
      try lines([
        ["type": "event_msg", "payload": ["type": "task_started", "turn_id": "turn-tail"]]
      ]))
    try content.write(to: file)

    let source = JSONLTranscriptEventSource(
      sessionsRoot: fixture.root,
      startPosition: .end,
      maximumTrackedFiles: 1,
      bootstrapTailBytes: 64 * 1_024
    )
    try source.prime()
    XCTAssertTrue(try source.poll().events.isEmpty)

    try append(
      try lines([
        [
          "type": "response_item",
          "payload": [
            "id": "message-tail", "type": "message", "role": "assistant",
            "phase": "commentary",
            "content": [["type": "output_text", "text": "Nouveau."]],
          ],
        ]
      ]), to: file)
    let event = try XCTUnwrap(try source.poll().events.first)
    guard case .assistantMessageCompleted(let message) = event.payload else {
      return XCTFail("Message assistant attendu")
    }
    XCTAssertEqual(message.threadID, "thread-large")
    XCTAssertEqual(message.turnID, "turn-tail")
  }

  func testRewrittenFileIsReparsedButCompositePreventsReplay() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let file = fixture.root.appendingPathComponent("session.jsonl")
    let content = try lines([
      ["type": "session_meta", "payload": ["id": "thread-1", "thread_source": "user"]],
      ["type": "event_msg", "payload": ["type": "task_started", "turn_id": "turn-1"]],
      [
        "type": "event_msg",
        "payload": [
          "type": "item_completed", "turn_id": "turn-1",
          "item": [
            "id": "message-1", "type": "AgentMessage", "phase": "final_answer",
            "content": [["type": "Text", "text": "Terminé."]],
          ],
        ],
      ],
    ])
    try content.write(to: file)
    let source = JSONLTranscriptEventSource(
      sessionsRoot: fixture.root,
      startPosition: .beginning,
      maximumTrackedFiles: 1
    )
    let composite = CompositeCodexEventSource()
    try source.prime()
    let initial = composite.ingest(try source.poll().events)
    XCTAssertGreaterThan(initial.filter(\.isNewTimelineEvent).count, 0)

    try Data().write(to: file)
    _ = try source.poll()
    try content.write(to: file)
    let replay = composite.ingest(try source.poll().events)
    XCTAssertEqual(replay.filter(\.isNewTimelineEvent).count, 0)
  }

  func testStartAtEndDoesNotReplayAReplacedTranscript() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let file = fixture.root.appendingPathComponent("session.jsonl")
    var initial = try lines([
      ["type": "session_meta", "payload": ["id": "thread-1", "thread_source": "user"]],
      ["type": "event_msg", "payload": ["type": "task_started", "turn_id": "turn-old"]],
    ])
    initial.append(Data(repeating: 0x20, count: 8_192))
    initial.append(0x0A)
    try initial.write(to: file)

    let source = JSONLTranscriptEventSource(
      sessionsRoot: fixture.root,
      startPosition: .end,
      maximumTrackedFiles: 1
    )
    try source.prime()

    try lines([
      ["type": "session_meta", "payload": ["id": "thread-1", "thread_source": "user"]],
      ["type": "event_msg", "payload": ["type": "task_started", "turn_id": "turn-new"]],
      [
        "type": "event_msg",
        "payload": [
          "type": "item_completed", "turn_id": "turn-new",
          "item": [
            "id": "historical-after-replacement", "type": "AgentMessage",
            "phase": "final_answer",
            "content": [["type": "Text", "text": "Historique remplacé."]],
          ],
        ],
      ],
    ]).write(to: file)

    let replacement = try source.poll()
    XCTAssertTrue(replacement.events.isEmpty)

    try append(
      try lines([
        [
          "type": "response_item",
          "payload": [
            "id": "live-after-replacement", "type": "message", "role": "assistant",
            "phase": "commentary",
            "content": [["type": "output_text", "text": "Nouveau."]],
          ],
        ]
      ]), to: file)
    let live = try XCTUnwrap(try source.poll().events.first)
    guard case .assistantMessageCompleted(let message) = live.payload else {
      return XCTFail("Message assistant attendu")
    }
    XCTAssertEqual(message.turnID, "turn-new")
    XCTAssertEqual(message.itemID, "live-after-replacement")
  }

  func testSubagentTranscriptIsIgnored() throws {
    let normalizer = JSONLTranscriptNormalizer()
    let metadata = normalizer.normalize(
      line: try jsonLine([
        "type": "session_meta",
        "payload": ["id": "thread-child", "thread_source": "subagent"],
      ]))
    let turn = normalizer.normalize(
      line: try jsonLine([
        "type": "event_msg",
        "payload": ["type": "task_started", "turn_id": "turn-child"],
      ]))
    XCTAssertTrue(metadata.events.isEmpty)
    XCTAssertTrue(turn.events.isEmpty)
    XCTAssertTrue(normalizer.isSubagent)
  }

  func testUserResponseItemIsIgnoredInFavorOfCompletedItem() throws {
    let normalizer = JSONLTranscriptNormalizer()
    _ = normalizer.normalize(
      line: try jsonLine([
        "type": "session_meta",
        "payload": ["id": "thread-1", "thread_source": "user"],
      ]))
    _ = normalizer.normalize(
      line: try jsonLine([
        "type": "event_msg",
        "payload": ["type": "task_started", "turn_id": "turn-1"],
      ]))
    let response = normalizer.normalize(
      line: try jsonLine([
        "type": "response_item",
        "payload": [
          "id": "msg-response", "type": "message", "role": "user",
          "content": [["type": "input_text", "text": "Texte privé non retenu."]],
        ],
      ]))
    let completed = normalizer.normalize(
      line: try jsonLine([
        "type": "event_msg",
        "payload": [
          "type": "item_completed", "turn_id": "turn-1",
          "item": ["id": "user-stable", "type": "UserMessage", "content": []],
        ],
      ]))
    XCTAssertTrue(response.events.isEmpty)
    XCTAssertEqual(completed.events.count, 1)
  }

  func testSourceCanTargetAnExplicitThread() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    try lines([
      ["type": "session_meta", "payload": ["id": "thread-keep", "thread_source": "user"]]
    ]).write(to: fixture.root.appendingPathComponent("rollout-thread-keep.jsonl"))
    try lines([
      ["type": "session_meta", "payload": ["id": "thread-skip", "thread_source": "user"]]
    ]).write(to: fixture.root.appendingPathComponent("rollout-thread-skip.jsonl"))

    let source = JSONLTranscriptEventSource(
      sessionsRoot: fixture.root,
      startPosition: .beginning,
      maximumTrackedFiles: 2,
      includedThreadIDs: ["thread-keep"]
    )
    try source.prime()
    let events = try source.poll().events
    XCTAssertEqual(events.count, 1)
    XCTAssertEqual(events.first?.payload.threadID, "thread-keep")
  }

  func testEventsFromDifferentFilesAreOrderedByCodexTimestamp() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    try lines([
      [
        "timestamp": "2026-08-31T20:00:00.000Z", "type": "session_meta",
        "payload": ["id": "thread-later", "thread_source": "user"],
      ],
      [
        "timestamp": "2026-08-31T20:00:02.000Z", "type": "event_msg",
        "payload": ["type": "task_started", "turn_id": "turn-later"],
      ],
      [
        "timestamp": "2026-08-31T20:00:04.000Z", "type": "event_msg",
        "payload": [
          "type": "item_completed", "turn_id": "turn-later",
          "item": ["id": "user-later", "type": "UserMessage", "content": []],
        ],
      ],
    ]).write(to: fixture.root.appendingPathComponent("rollout-thread-later.jsonl"))
    try lines([
      [
        "timestamp": "2026-08-31T20:00:01.000Z", "type": "session_meta",
        "payload": ["id": "thread-earlier", "thread_source": "user"],
      ],
      [
        "timestamp": "2026-08-31T20:00:02.500Z", "type": "event_msg",
        "payload": ["type": "task_started", "turn_id": "turn-earlier"],
      ],
      [
        "timestamp": "2026-08-31T20:00:03.000Z", "type": "event_msg",
        "payload": [
          "type": "item_completed", "turn_id": "turn-earlier",
          "item": ["id": "user-earlier", "type": "UserMessage", "content": []],
        ],
      ],
    ]).write(to: fixture.root.appendingPathComponent("rollout-thread-earlier.jsonl"))

    let source = JSONLTranscriptEventSource(
      sessionsRoot: fixture.root,
      startPosition: .beginning,
      maximumTrackedFiles: 2
    )
    try source.prime()
    let users = try source.poll().events.compactMap { event -> String? in
      guard case .userMessageCompleted(let message) = event.payload else { return nil }
      return message.threadID
    }
    XCTAssertEqual(users, ["thread-earlier", "thread-later"])
  }
}

extension CodexSourceEvent {
  fileprivate var isAssistantMessage: Bool {
    if case .assistantMessageCompleted = payload { return true }
    return false
  }
}

private struct Fixture {
  let root: URL

  init() throws {
    root = FileManager.default.temporaryDirectory
      .appendingPathComponent("codex-voice-core-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  }

  func remove() {
    try? FileManager.default.removeItem(at: root)
  }
}

private func jsonLine(_ object: [String: Any]) throws -> Data {
  try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
}

private func lines(_ objects: [[String: Any]]) throws -> Data {
  var result = Data()
  for object in objects {
    result.append(try jsonLine(object))
    result.append(0x0A)
  }
  return result
}

private func append(_ data: Data, to url: URL) throws {
  let handle = try FileHandle(forWritingTo: url)
  defer { try? handle.close() }
  try handle.seekToEnd()
  try handle.write(contentsOf: data)
}
