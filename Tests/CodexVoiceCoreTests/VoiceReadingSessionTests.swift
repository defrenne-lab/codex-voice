import Foundation
import XCTest

@testable import CodexVoiceCore

@MainActor
final class VoiceReadingSessionTests: XCTestCase {
  func testIndexAuthorityDoesNotHideAJournalObservedAfterItsTitle() {
    let test = SessionFixture()
    test.session.process(
      test.composite.ingest(
        .init(
          timestamp: test.clock.date,
          origin: .sessionIndex, authority: .sessionIndex,
          payload: .threadObserved(.init(threadID: "B", title: "Travail long", isSubagent: false))))
    )
    test.send(
      .threadObserved(.init(threadID: "B", title: nil, isSubagent: false)), historical: true)
    XCTAssertTrue(test.session.conversations.contains { $0.threadID == "B" })
    XCTAssertTrue(test.session.selectConversation("B"))
    XCTAssertEqual(test.session.mainConversation?.threadTitle, "Travail long")
    XCTAssertTrue(test.driver.requests.isEmpty)
  }

  func testKnownHistoricalMessageRehydratesAfterMemoryEvictionWithoutSpeaking() {
    let test = SessionFixture(history: VoiceRecentHistory(maximumThreads: 1))
    test.answer("A", item: "old-A", text: "Réponse A.", historical: true)
    test.answer("B", item: "old-B", text: "Réponse B.", historical: true)
    XCTAssertTrue(test.session.history.blocks(for: "A").isEmpty)
    test.answer("A", item: "old-A", text: "Réponse A.", historical: true)
    XCTAssertEqual(test.session.history.blocks(for: "A").first?.text, "Réponse A.")
    XCTAssertTrue(test.driver.requests.isEmpty)
    XCTAssertNil(test.session.mainConversation)
  }

  func testLongRunningObservedJournalWithoutTurnContextCanBeSelected() {
    let test = SessionFixture()
    test.send(
      .threadObserved(.init(threadID: "B", title: "Traitement long", isSubagent: false)),
      historical: true)
    test.user("A")
    XCTAssertTrue(test.session.conversations.contains { $0.threadID == "B" })
    XCTAssertTrue(test.session.selectConversation("B"))
    XCTAssertTrue(test.driver.requests.isEmpty)
    test.answer("B", item: "next", text: "Le traitement est terminé.")
    XCTAssertEqual(test.session.mainConversation?.turnID, "B1")
    XCTAssertEqual(test.driver.requests.last?.text, "Le traitement est terminé.")
  }

  func testIndexOnlyTaskIsNotSelectableAndManyTitlesDoNotEvictObservedTask() {
    let test = SessionFixture()
    test.send(
      .threadObserved(.init(threadID: "observed", title: "Tâche en cours", isSubagent: false)),
      historical: true)
    for index in 0..<200 {
      test.session.process(
        test.composite.ingest(
          .init(
            timestamp: test.clock.date,
            origin: .sessionIndex, authority: .sessionIndex,
            payload: .threadObserved(
              .init(threadID: "index-\(index)", title: "Ancienne tâche", isSubagent: false)))))
    }
    XCTAssertTrue(test.session.conversations.contains { $0.threadID == "observed" })
    XCTAssertFalse(test.session.selectConversation("index-199"))
    XCTAssertTrue(test.session.selectConversation("observed"))
  }

  func testSelectLongRunningTaskWithoutNewUserMessageOnlyReadsFutureBlocks() throws {
    let test = SessionFixture()
    test.send(.turnStarted(.init(threadID: "B", turnID: "B1")), historical: true)
    test.answer("B", item: "old", text: "Ancien résultat.", historical: true)
    test.user("A")
    XCTAssertTrue(test.session.selectConversation("B"))
    XCTAssertEqual(test.session.mainConversation?.threadID, "B")
    XCTAssertTrue(test.driver.requests.isEmpty)
    test.answer("B", item: "fresh", text: "Nouveau résultat.")
    XCTAssertEqual(test.driver.requests.last?.text, "Nouveau résultat.")
    test.answer("A", item: "parallel", text: "Ne doit pas couper.")
    XCTAssertEqual(test.driver.requests.count, 1)
    test.user("A", item: "second-user")
    XCTAssertEqual(test.session.mainConversation?.threadID, "A")
    XCTAssertNil(test.audio.snapshot.currentUnit)
  }

  func testHistoryCanReplaySilentTaskBlockByBlockAndStopsAtBounds() {
    let test = SessionFixture()
    test.send(.turnStarted(.init(threadID: "B", turnID: "B1")), historical: true)
    test.answer("B", item: "old", text: "Un.\n\nDeux.\n\nTrois.", historical: true)
    XCTAssertTrue(test.session.selectConversation("B"))
    XCTAssertTrue(test.session.navigation.canGoPrevious)
    XCTAssertFalse(test.session.navigation.canGoNext)
    XCTAssertTrue(test.session.navigate(forward: false))
    XCTAssertEqual(test.driver.requests.last?.text, "Trois.")
    XCTAssertTrue(test.session.navigate(forward: false))
    XCTAssertEqual(test.driver.requests.last?.text, "Deux.")
    XCTAssertTrue(test.session.navigate(forward: false))
    XCTAssertEqual(test.driver.requests.last?.text, "Un.")
    XCTAssertFalse(test.session.navigate(forward: false))
    XCTAssertTrue(test.session.navigate(forward: true))
    XCTAssertEqual(test.driver.requests.last?.text, "Deux.")
    test.session.interrupt()
    test.clock.date += 60
    test.session.tick()
    XCTAssertNil(test.audio.snapshot.currentUnit)
    XCTAssertEqual(test.audio.snapshot.queuedUnitCount, 0)
  }

  func testNotificationsWaitTenSecondsAfterLastMainBlockAndTwoBetweenSummaries() {
    let test = SessionFixture()
    test.user("A")
    test.answer("A", item: "main", text: "Premier paragraphe.\n\nDeuxième paragraphe.")
    test.parallel(
      "B", title: "Améliorer la fusion des tâches", text: "Les traitements sont terminés.")
    test.parallel("C", title: "Autre tâche", text: "Trois tests ont réussi.")
    test.clock.date += 20
    test.session.tick()
    XCTAssertEqual(test.driver.requests.count, 1)
    test.driver.finish()
    XCTAssertEqual(test.driver.requests.count, 2)
    test.driver.finish()
    test.clock.date += 9.9
    test.session.tick()
    XCTAssertEqual(test.driver.requests.count, 2)
    test.clock.date += 0.1
    test.session.tick()
    XCTAssertEqual(
      test.driver.requests.last?.text, "Améliorer la fusion. Les traitements sont terminés.")
    XCTAssertTrue(test.driver.requests.last?.notificationCue == true)
    XCTAssertEqual(test.session.mainConversation?.threadID, "A")
    test.driver.finish()
    test.clock.date += 1.9
    test.session.tick()
    XCTAssertEqual(test.driver.requests.count, 3)
    test.clock.date += 0.1
    test.session.tick()
    XCTAssertEqual(test.driver.requests.count, 4)
    XCTAssertEqual(test.audio.snapshot.currentUnit?.threadID, "C")
  }

  func testOneInterruptDuringNotificationGapDiscardsWholeBatch() {
    let test = SessionFixture()
    test.user("A")
    for thread in ["B", "C", "D"] { test.parallel(thread, text: "Tout est prêt.") }
    test.clock.date += 10
    test.session.tick()
    test.driver.finish()
    XCTAssertTrue(test.session.interrupt())
    test.clock.date += 60
    test.session.tick()
    XCTAssertEqual(test.driver.requests.count, 1)
    XCTAssertEqual(test.session.pendingNotificationCount, 0)
  }

  func testMainSpeechBetweenNotificationsRestartsTenSecondQuietPeriod() {
    let test = SessionFixture()
    test.user("A")
    test.parallel("B", text: "Premier résultat.")
    test.parallel("C", text: "Deuxième résultat.")
    test.clock.date += 10
    test.session.tick()
    test.driver.finish()
    test.answer("A", item: "new-main", text: "Réponse principale prioritaire.")
    test.driver.finish()
    test.clock.date += 9
    test.session.tick()
    XCTAssertEqual(test.driver.requests.count, 2)
    test.clock.date += 1
    test.session.tick()
    XCTAssertEqual(test.driver.requests.count, 3)
    XCTAssertEqual(test.audio.snapshot.currentUnit?.threadID, "C")
  }

  func testMainResponsePreemptsNotificationAndDisableNeverReplaysPendingSummaries() {
    let test = SessionFixture()
    test.user("A")
    test.parallel("B", text: "Tout est prêt.")
    test.parallel("C", text: "Un autre résultat.")
    test.clock.date += 10
    test.session.tick()
    XCTAssertEqual(test.audio.snapshot.currentUnit?.kind, .notification)
    test.answer("A", item: "main", text: "Réponse principale.")
    XCTAssertEqual(test.audio.snapshot.currentUnit?.threadID, "A")
    XCTAssertEqual(test.session.pendingNotificationCount, 0)
    test.parallel("D", text: "Encore un résultat.")
    test.audio.setVoiceEnabled(false)
    test.audio.setVoiceEnabled(true)
    test.clock.date += 60
    test.session.tick()
    XCTAssertNil(test.audio.snapshot.currentUnit)
    XCTAssertEqual(test.session.pendingNotificationCount, 0)
  }

  func testHistoryKeepsFiveMessagesReplacesCorrectionsAndSupersededProgress() {
    let history = VoiceRecentHistory(maximumMessages: 5, maximumThreads: 2)
    for index in 0..<8 {
      history.store(
        .init(
          threadID: "A", turnID: "turn\(index)", itemID: "item\(index)",
          phase: .finalAnswer, text: "Message \(index).\n\nSecond bloc."))
    }
    XCTAssertEqual(history.blocks(for: "A").count, 10)
    XCTAssertEqual(history.blocks(for: "A").first?.itemID, "item3")
    history.store(
      .init(threadID: "A", turnID: "turn7", itemID: "item7", phase: .finalAnswer, text: "Corrigé."))
    XCTAssertEqual(history.blocks(for: "A").last?.text, "Corrigé.")
    XCTAssertEqual(history.blocks(for: "A").count, 9)
    history.store(
      .init(
        threadID: "B", turnID: "turn", itemID: "progress", phase: .commentary, text: "Je vérifie."))
    history.store(
      .init(threadID: "B", turnID: "turn", itemID: "final", phase: .finalAnswer, text: "Terminé."))
    XCTAssertEqual(history.blocks(for: "B").count, 1)
    history.store(
      .init(
        threadID: "C", turnID: "turn", itemID: "item", phase: .finalAnswer, text: "Troisième tâche."
      ))
    XCTAssertTrue(history.blocks(for: "A").isEmpty)
  }

  func testTechnicalBlocksAreRepresentedWithoutReadingCodeAndSummaryIsBounded() {
    let blocks = VoiceReadableText.blocks(
      "Résultat.\n\n```swift\nprint(\"secret\")\n```\n\nVoir [GitHub](https://example.com).")
    XCTAssertEqual(blocks, ["Résultat.", "Bloc de code disponible à l’écran.", "Voir GitHub."])
    let summary = VoiceReadableText.notificationSummary(
      String(repeating: "Les tests ont échoué et nécessitent une correction. ", count: 300))
    XCTAssertTrue(summary.contains("échoué"))
    XCTAssertLessThanOrEqual(summary.count, 181)
  }

  func testUnknownFinalPhaseReplacesProgressWhenTurnCompletes() {
    let history = VoiceRecentHistory()
    history.store(
      .init(
        threadID: "A", turnID: "turn", itemID: "progress", phase: .commentary, text: "Je vérifie."))
    history.store(
      .init(
        threadID: "A", turnID: "turn", itemID: "final", phase: .unknown(nil),
        text: "Résultat final."))
    history.finishTurn(threadID: "A", turnID: "turn")
    XCTAssertEqual(history.blocks(for: "A").map(\.text), ["Résultat final."])
    history.store(
      .init(
        threadID: "A", turnID: "turn", itemID: "progress", phase: .commentary,
        text: "Ancien progrès."))
    XCTAssertEqual(history.blocks(for: "A").map(\.text), ["Résultat final."])
  }

  func testCompositeDeduplicationMemoryIsBounded() {
    let composite = CompositeCodexEventSource(maximumEvents: 3)
    for index in 0..<10 {
      _ = composite.ingest(
        .init(
          timestamp: nil, origin: .jsonlLifecycle, authority: .jsonlCompleted,
          payload: .turnStarted(.init(threadID: "A", turnID: "\(index)"))))
    }
    XCTAssertEqual(composite.knownEventCount, 3)
  }
}

@MainActor
private final class SessionFixture {
  final class Clock { var date = Date(timeIntervalSince1970: 1_000) }
  let clock = Clock()
  let driver = SessionSpeechDriver()
  let audio: VoiceAudioCoordinator
  let session: VoiceReadingSession
  let composite = CompositeCodexEventSource()
  init(history: VoiceRecentHistory = VoiceRecentHistory()) {
    audio = VoiceAudioCoordinator(driver: driver, defaultSettings: .init(isEnabled: true))
    let clock = clock
    session = VoiceReadingSession(audio: audio, history: history, now: { clock.date })
  }
  func send(_ payload: CodexEventPayload, historical: Bool = false) {
    session.process(
      composite.ingest(
        .init(
          timestamp: clock.date,
          origin: historical ? .transcriptHistory : .jsonlCompletedItem, authority: .jsonlCompleted,
          payload: payload)))
  }
  func user(_ thread: String, item: String = "user") {
    send(.userMessageCompleted(.init(threadID: thread, turnID: thread + "1", itemID: item)))
  }
  func answer(_ thread: String, item: String, text: String, historical: Bool = false) {
    send(
      .assistantMessageCompleted(
        .init(
          threadID: thread, turnID: thread + "1", itemID: item,
          phase: .finalAnswer, text: text)), historical: historical)
  }
  func parallel(_ thread: String, title: String? = nil, text: String) {
    send(.threadObserved(.init(threadID: thread, title: title, isSubagent: false)))
    answer(thread, item: "answer", text: text)
    send(.turnCompleted(.init(threadID: thread, turnID: thread + "1", status: "completed")))
  }
}

@MainActor
private final class SessionSpeechDriver: VoiceSpeechDriver {
  var completionHandler: ((String, VoiceSpeechDriverOutcome) -> Void)?
  var requests: [VoiceSpeechDriverRequest] = []
  func speak(_ request: VoiceSpeechDriverRequest) { requests.append(request) }
  func stop() {}
  func finish() { if let request = requests.last { completionHandler?(request.unitID, .finished) } }
}
