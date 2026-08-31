import XCTest

@testable import CodexVoiceProbe

final class ProbeTests: XCTestCase {
  func testHistoryReconstructionIsDeduplicatedAndCountsPhases() throws {
    let store = try ProbeCheckpointStore(fileURL: nil)
    let thread: JSONObject = [
      "id": "thread-1",
      "turns": [
        [
          "id": "turn-1",
          "status": "completed",
          "items": [
            ["id": "user-1", "type": "userMessage", "content": []],
            [
              "id": "agent-1", "type": "agentMessage", "phase": "commentary", "text": "Je vérifie.",
            ],
            ["id": "agent-2", "type": "agentMessage", "phase": "final_answer", "text": "Terminé."],
            ["id": "command-1", "type": "commandExecution", "status": "completed"],
          ],
        ],
        [
          "id": "turn-2",
          "status": "completed",
          "items": [
            ["id": "agent-3", "type": "agentMessage", "text": "Phase absente."]
          ],
        ],
      ],
    ]

    let first = HistoryAnalyzer.analyze(thread: thread, checkpointStore: store)
    XCTAssertEqual(first.newlyObserved, 4)
    XCTAssertEqual(first.alreadyKnown, 0)
    XCTAssertEqual(first.phaseCounts["commentary"], 1)
    XCTAssertEqual(first.phaseCounts["final_answer"], 1)
    XCTAssertEqual(first.phaseCounts["missing"], 1)

    let second = HistoryAnalyzer.analyze(thread: thread, checkpointStore: store)
    XCTAssertEqual(second.newlyObserved, 0)
    XCTAssertEqual(second.alreadyKnown, 4)
  }

  func testCompletedUserMessageSelectsMainThread() throws {
    let store = try ProbeCheckpointStore(fileURL: nil)
    let recorder = EventRecorder(includeText: false, checkpointStore: store)

    recorder.record([
      "method": "item/completed",
      "params": [
        "threadId": "thread-main",
        "turnId": "turn-1",
        "item": ["id": "user-1", "type": "userMessage", "content": []],
      ],
    ])

    XCTAssertEqual(recorder.lastUserThreadID, "thread-main")
    XCTAssertEqual(recorder.stableItemsNew, 1)
    XCTAssertEqual(recorder.methodCounts["item/completed"], 1)
  }

  func testThreadStatusSupportsObjectAndStringForms() {
    XCTAssertEqual(ProbeRunner.statusName(from: "idle"), "idle")
    XCTAssertEqual(ProbeRunner.statusName(from: ["type": "active"]), "active")
    XCTAssertEqual(ProbeRunner.statusName(from: nil), "unknown")
  }
}
