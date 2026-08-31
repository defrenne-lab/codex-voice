import Foundation
import XCTest

@testable import CodexVoiceCore

final class VoiceOrchestratorTests: XCTestCase {
  func testLastLiveUserMessageSelectsMainConversation() {
    let pipeline = RoutingPipeline()
    let first = pipeline.send(userMessage(thread: "A", turn: "A1", item: "user-A1"))
    XCTAssertEqual(first.mainChange?.current, conversation("A", "A1"))

    let second = pipeline.send(userMessage(thread: "B", turn: "B1", item: "user-B1"))
    XCTAssertEqual(second.mainChange?.previous, conversation("A", "A1"))
    XCTAssertEqual(second.mainChange?.current, conversation("B", "B1"))
    XCTAssertEqual(pipeline.orchestrator.mainConversation, conversation("B", "B1"))
  }

  func testLateOlderUserEventCannotStealMainConversation() {
    let pipeline = RoutingPipeline()
    let newer = Date(timeIntervalSince1970: 200)
    let older = Date(timeIntervalSince1970: 100)
    _ = pipeline.send(
      userMessage(thread: "A", turn: "A1", item: "user-A1"),
      timestamp: newer
    )
    let late = pipeline.send(
      userMessage(thread: "B", turn: "B1", item: "user-B1"),
      timestamp: older
    )
    XCTAssertTrue(late.isEmpty)
    XCTAssertEqual(pipeline.orchestrator.mainConversation, conversation("A", "A1"))
  }

  func testOnlyCommentaryFromCurrentMainTurnRequestsSpeech() {
    let pipeline = RoutingPipeline()
    _ = pipeline.send(userMessage(thread: "A", turn: "A2", item: "user-A2"))

    XCTAssertTrue(
      pipeline.send(commentary(thread: "A", turn: "A1", item: "old")).isEmpty)
    XCTAssertTrue(
      pipeline.send(commentary(thread: "B", turn: "B1", item: "parallel")).isEmpty)

    let current = pipeline.send(commentary(thread: "A", turn: "A2", item: "current"))
    XCTAssertEqual(current.speechRequests.count, 1)
    XCTAssertEqual(current.speechRequests.first?.kind, .commentary)
    XCTAssertEqual(current.speechRequests.first?.itemID, "current")
  }

  func testMainFinalAnswerIsRequestedOnlyOnceAcrossDuplicateAndSnapshot() {
    let pipeline = RoutingPipeline()
    _ = pipeline.send(userMessage(thread: "A", turn: "A1", item: "user-A1"))
    let payload = finalAnswer(thread: "A", turn: "A1", item: "final-A1")

    XCTAssertEqual(pipeline.send(payload).speechRequests.first?.kind, .finalAnswer)
    XCTAssertTrue(
      pipeline.send(payload, origin: .jsonlResponseItem, authority: .jsonlFallback).isEmpty)
    XCTAssertTrue(
      pipeline.send(payload, origin: .appServerSnapshot, authority: .appServerSnapshot).isEmpty)
    XCTAssertTrue(pipeline.send(turnCompleted(thread: "A", turn: "A1")).isEmpty)
  }

  func testParallelFinalWaitsForTurnCompletionAndBecomesPending() {
    let pipeline = RoutingPipeline()
    _ = pipeline.send(userMessage(thread: "A", turn: "A1", item: "user-A1"))
    XCTAssertTrue(
      pipeline.send(commentary(thread: "B", turn: "B1", item: "comment-B1")).isEmpty)
    XCTAssertTrue(
      pipeline.send(finalAnswer(thread: "B", turn: "B1", item: "final-B1")).isEmpty)

    let completion = pipeline.send(turnCompleted(thread: "B", turn: "B1"))
    XCTAssertEqual(completion.parallelResponses.count, 1)
    XCTAssertTrue(completion.speechRequests.isEmpty)
    XCTAssertEqual(pipeline.orchestrator.snapshot.pendingResponses.count, 1)
    XCTAssertEqual(pipeline.orchestrator.snapshot.pendingResponses.first?.itemID, "final-B1")
  }

  func testUnknownPhaseWaitsForCompletionBeforeSpeakingOnMainConversation() {
    let pipeline = RoutingPipeline()
    _ = pipeline.send(userMessage(thread: "A", turn: "A1", item: "user-A1"))
    XCTAssertTrue(pipeline.send(unknownAnswer(thread: "A", turn: "A1", item: "unknown")).isEmpty)

    let completion = pipeline.send(turnCompleted(thread: "A", turn: "A1"))
    XCTAssertEqual(completion.speechRequests.first?.kind, .finalAnswer)
    XCTAssertEqual(completion.speechRequests.first?.itemID, "unknown")
  }

  func testHistoricalSnapshotNeverSelectsMainOrCreatesSpeech() {
    let pipeline = RoutingPipeline()
    let user = userMessage(thread: "A", turn: "A1", item: "user-A1")
    XCTAssertTrue(
      pipeline.send(user, origin: .appServerSnapshot, authority: .appServerSnapshot).isEmpty)
    XCTAssertTrue(
      pipeline.send(
        finalAnswer(thread: "A", turn: "A1", item: "final-A1"),
        origin: .appServerSnapshot,
        authority: .appServerSnapshot
      ).isEmpty)
    XCTAssertTrue(
      pipeline.send(
        turnCompleted(thread: "A", turn: "A1"),
        origin: .appServerSnapshot,
        authority: .appServerSnapshot
      ).isEmpty)
    XCTAssertNil(pipeline.orchestrator.mainConversation)
    XCTAssertTrue(pipeline.orchestrator.snapshot.pendingResponses.isEmpty)

    let liveDuplicate = pipeline.send(user)
    XCTAssertEqual(liveDuplicate.mainChange?.current, conversation("A", "A1"))
  }

  func testFailedParallelTurnDoesNotCreatePendingResponse() {
    let pipeline = RoutingPipeline()
    _ = pipeline.send(userMessage(thread: "A", turn: "A1", item: "user-A1"))
    _ = pipeline.send(finalAnswer(thread: "B", turn: "B1", item: "final-B1"))
    XCTAssertTrue(
      pipeline.send(turnCompleted(thread: "B", turn: "B1", status: "failed")).isEmpty)
    XCTAssertTrue(pipeline.orchestrator.snapshot.pendingResponses.isEmpty)
  }

  func testSnapshotTitleCorrectionEnrichesPendingResponseWithoutNewEffect() {
    let pipeline = RoutingPipeline()
    _ = pipeline.send(threadMetadata(thread: "B", title: nil))
    _ = pipeline.send(userMessage(thread: "A", turn: "A1", item: "user-A1"))
    _ = pipeline.send(finalAnswer(thread: "B", turn: "B1", item: "final-B1"))
    _ = pipeline.send(turnCompleted(thread: "B", turn: "B1"))
    XCTAssertNil(pipeline.orchestrator.snapshot.pendingResponses.first?.threadTitle)

    let correction = pipeline.send(
      threadMetadata(thread: "B", title: "Optimiser GitHub"),
      origin: .appServerSnapshot,
      authority: .appServerSnapshot
    )
    XCTAssertTrue(correction.isEmpty)
    XCTAssertEqual(
      pipeline.orchestrator.snapshot.pendingResponses.first?.threadTitle,
      "Optimiser GitHub"
    )
  }

  func testSendingANewMessageClearsPendingResponsesForThatThread() {
    let pipeline = RoutingPipeline()
    _ = pipeline.send(userMessage(thread: "A", turn: "A1", item: "user-A1"))
    _ = pipeline.send(finalAnswer(thread: "B", turn: "B1", item: "final-B1"))
    _ = pipeline.send(turnCompleted(thread: "B", turn: "B1"))
    XCTAssertEqual(pipeline.orchestrator.snapshot.pendingResponses.count, 1)

    let effects = pipeline.send(userMessage(thread: "B", turn: "B2", item: "user-B2"))
    XCTAssertEqual(effects.mainChange?.current, conversation("B", "B2"))
    XCTAssertEqual(effects.clearedResponses.first?.count, 1)
    XCTAssertTrue(pipeline.orchestrator.snapshot.pendingResponses.isEmpty)
  }
}

private final class RoutingPipeline {
  let composite = CompositeCodexEventSource()
  let orchestrator = VoiceOrchestrator()

  func send(
    _ payload: CodexEventPayload,
    origin: CodexEventOrigin = .jsonlCompletedItem,
    authority: CodexEventAuthority = .jsonlCompleted,
    timestamp: Date? = nil
  ) -> [VoiceOrchestratorEffect] {
    let event = CodexSourceEvent(
      timestamp: timestamp,
      origin: origin,
      authority: authority,
      payload: payload
    )
    return orchestrator.process(composite.ingest(event))
  }
}

extension Array where Element == VoiceOrchestratorEffect {
  fileprivate var mainChange: VoiceMainConversationChange? {
    for effect in self {
      if case .mainConversationChanged(let change) = effect { return change }
    }
    return nil
  }

  fileprivate var speechRequests: [VoiceSpeechRequest] {
    compactMap {
      if case .speechRequested(let request) = $0 { return request }
      return nil
    }
  }

  fileprivate var parallelResponses: [VoicePendingResponse] {
    compactMap {
      if case .parallelResponseReady(let response) = $0 { return response }
      return nil
    }
  }

  fileprivate var clearedResponses: [VoicePendingResponsesCleared] {
    compactMap {
      if case .pendingResponsesCleared(let response) = $0 { return response }
      return nil
    }
  }
}

private func conversation(_ threadID: String, _ turnID: String) -> VoiceConversationReference {
  VoiceConversationReference(threadID: threadID, turnID: turnID)
}

private func threadMetadata(thread: String, title: String?) -> CodexEventPayload {
  .threadObserved(CodexThreadMetadata(threadID: thread, title: title, isSubagent: false))
}

private func userMessage(thread: String, turn: String, item: String) -> CodexEventPayload {
  .userMessageCompleted(
    CodexUserMessageReference(threadID: thread, turnID: turn, itemID: item)
  )
}

private func commentary(thread: String, turn: String, item: String) -> CodexEventPayload {
  assistantMessage(thread: thread, turn: turn, item: item, phase: .commentary)
}

private func finalAnswer(thread: String, turn: String, item: String) -> CodexEventPayload {
  assistantMessage(thread: thread, turn: turn, item: item, phase: .finalAnswer)
}

private func unknownAnswer(thread: String, turn: String, item: String) -> CodexEventPayload {
  assistantMessage(thread: thread, turn: turn, item: item, phase: .unknown(nil))
}

private func assistantMessage(
  thread: String,
  turn: String,
  item: String,
  phase: CodexMessagePhase
) -> CodexEventPayload {
  .assistantMessageCompleted(
    CodexAssistantMessage(
      threadID: thread,
      turnID: turn,
      itemID: item,
      phase: phase,
      text: "Texte \(item)"
    )
  )
}

private func turnCompleted(
  thread: String,
  turn: String,
  status: String = "completed"
) -> CodexEventPayload {
  .turnCompleted(CodexTurnCompletion(threadID: thread, turnID: turn, status: status))
}
