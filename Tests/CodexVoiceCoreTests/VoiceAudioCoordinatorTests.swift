import Foundation
import XCTest

@testable import CodexVoiceCore

@MainActor
final class VoiceAudioCoordinatorTests: XCTestCase {
  func testSafeDefaultRejectsAudioUntilExplicitlyEnabled() {
    let driver = FakeSpeechDriver()
    let coordinator = VoiceAudioCoordinator(driver: driver)

    XCTAssertFalse(coordinator.settings.isEnabled)
    XCTAssertEqual(coordinator.enqueue(unit(item: "one")), .ignoredVoiceDisabled)
    XCTAssertTrue(driver.requests.isEmpty)
  }

  func testQueueNeverPreemptsAndAdvancesAfterCompletion() throws {
    let driver = FakeSpeechDriver()
    let coordinator = enabledCoordinator(driver: driver)

    XCTAssertEqual(coordinator.enqueue(unit(item: "one")), .started)
    XCTAssertEqual(coordinator.enqueue(unit(item: "two")), .queued)
    XCTAssertEqual(driver.requests.map(\.unitID), [unit(item: "one").id])
    XCTAssertEqual(coordinator.snapshot.queuedUnitCount, 1)

    driver.completeCurrent(.finished)
    XCTAssertEqual(driver.requests.map(\.unitID), [unit(item: "one").id, unit(item: "two").id])
    XCTAssertEqual(coordinator.snapshot.currentUnit?.itemID, "two")
  }

  func testInterruptDiscardsWholeQueueAndDismissesItsTurns() {
    let driver = FakeSpeechDriver()
    let coordinator = enabledCoordinator(driver: driver)
    _ = coordinator.enqueue(unit(turn: "turn-1", item: "one"))
    _ = coordinator.enqueue(unit(turn: "turn-1", item: "two"))

    XCTAssertTrue(coordinator.interrupt())
    XCTAssertEqual(driver.stopCalls, 1)
    XCTAssertNil(coordinator.snapshot.currentUnit)
    XCTAssertEqual(coordinator.snapshot.queuedUnitCount, 0)
    XCTAssertEqual(
      coordinator.enqueue(unit(turn: "turn-1", item: "three")),
      .ignoredDismissedGroup
    )
    XCTAssertEqual(coordinator.enqueue(unit(turn: "turn-2", item: "four")), .started)
  }

  func testInterruptAllowsFreshInteractionInsideSameCodexTurn() {
    let driver = FakeSpeechDriver()
    let coordinator = enabledCoordinator(driver: driver)
    _ = coordinator.enqueue(
      unit(group: "interaction|thread-1|turn-1|user-one", turn: "turn-1", item: "one")
    )

    XCTAssertTrue(coordinator.interrupt())
    XCTAssertEqual(
      coordinator.enqueue(
        unit(group: "interaction|thread-1|turn-1|user-one", turn: "turn-1", item: "late")
      ),
      .ignoredDismissedGroup
    )
    XCTAssertEqual(
      coordinator.enqueue(
        unit(group: "interaction|thread-1|turn-1|user-two", turn: "turn-1", item: "fresh")
      ),
      .started
    )
  }

  func testDisableStopsImmediatelyPersistsAndDoesNotReplayQueue() throws {
    let driver = FakeSpeechDriver()
    let store = MemorySettingsStore(
      settings: VoiceAudioSettings(isEnabled: true, isMuted: false)
    )
    let coordinator = VoiceAudioCoordinator(driver: driver, settingsStore: store)
    _ = coordinator.enqueue(unit(item: "one"))
    _ = coordinator.enqueue(unit(item: "two"))

    coordinator.setVoiceEnabled(false)
    XCTAssertEqual(driver.stopCalls, 1)
    XCTAssertFalse(try XCTUnwrap(store.saved.last).isEnabled)
    XCTAssertNil(coordinator.snapshot.currentUnit)
    XCTAssertEqual(coordinator.enqueue(unit(item: "three")), .ignoredVoiceDisabled)

    coordinator.setVoiceEnabled(true)
    XCTAssertEqual(coordinator.enqueue(unit(item: "four")), .started)
    XCTAssertEqual(driver.requests.last?.unitID, unit(item: "four").id)
  }

  func testMuteStopsImmediatelyAndFutureAudioWaitsForExplicitUnmute() {
    let driver = FakeSpeechDriver()
    let coordinator = enabledCoordinator(driver: driver)
    _ = coordinator.enqueue(unit(item: "one"))

    coordinator.setMuted(true)
    XCTAssertEqual(driver.stopCalls, 1)
    XCTAssertEqual(coordinator.enqueue(unit(item: "two")), .ignoredMuted)
    coordinator.setMuted(false)
    XCTAssertEqual(coordinator.enqueue(unit(item: "three")), .started)
  }

  func testRateAndVoiceAreClampedAndPersisted() throws {
    let driver = FakeSpeechDriver()
    let store = MemorySettingsStore()
    let coordinator = VoiceAudioCoordinator(driver: driver, settingsStore: store)

    coordinator.setRate(0)
    coordinator.setVoiceIdentifier("  voice-id  ")
    XCTAssertEqual(coordinator.settings.rate, 0.1)
    XCTAssertEqual(coordinator.settings.voiceIdentifier, "voice-id")
    XCTAssertEqual(try XCTUnwrap(store.saved.last).voiceIdentifier, "voice-id")
  }

  func testDuplicateUnitNeverPlaysTwiceEvenAfterCompletion() {
    let driver = FakeSpeechDriver()
    let coordinator = enabledCoordinator(driver: driver)
    let audioUnit = unit(item: "one")
    _ = coordinator.enqueue(audioUnit)
    driver.completeCurrent(.finished)

    XCTAssertEqual(coordinator.enqueue(audioUnit), .ignoredDuplicate)
    XCTAssertEqual(driver.requests.count, 1)
  }

  func testStaleDriverCompletionAfterInterruptIsIgnored() {
    let driver = FakeSpeechDriver()
    let coordinator = enabledCoordinator(driver: driver)
    let first = unit(item: "one")
    _ = coordinator.enqueue(first)
    _ = coordinator.enqueue(unit(item: "two"))
    _ = coordinator.interrupt()

    driver.completionHandler?(first.id, .cancelled)
    XCTAssertNil(coordinator.snapshot.currentUnit)
    XCTAssertEqual(driver.requests.count, 1)
  }
}

@MainActor
private final class FakeSpeechDriver: VoiceSpeechDriver {
  var completionHandler: ((String, VoiceSpeechDriverOutcome) -> Void)?
  var requests: [VoiceSpeechDriverRequest] = []
  var stopCalls = 0

  func speak(_ request: VoiceSpeechDriverRequest) {
    requests.append(request)
  }

  func stop() {
    stopCalls += 1
  }

  func completeCurrent(_ outcome: VoiceSpeechDriverOutcome) {
    guard let id = requests.last?.unitID else { return }
    completionHandler?(id, outcome)
  }
}

private final class MemorySettingsStore: VoiceAudioSettingsStore {
  private let initial: VoiceAudioSettings?
  var saved: [VoiceAudioSettings] = []

  init(settings: VoiceAudioSettings? = nil) {
    initial = settings
  }

  func load() -> VoiceAudioSettings? { initial }

  func save(_ settings: VoiceAudioSettings) {
    saved.append(settings)
  }
}

@MainActor
private func enabledCoordinator(driver: FakeSpeechDriver) -> VoiceAudioCoordinator {
  VoiceAudioCoordinator(
    driver: driver,
    defaultSettings: VoiceAudioSettings(isEnabled: true, isMuted: false)
  )
}

private func unit(
  group: String? = nil,
  thread: String = "thread-1",
  turn: String = "turn-1",
  item: String
) -> VoiceAudioUnit {
  VoiceAudioUnit(
    id: "item|\(thread)|\(turn)|\(item)",
    groupID: group ?? "turn|\(thread)|\(turn)",
    threadID: thread,
    turnID: turn,
    itemID: item,
    threadTitle: nil,
    kind: .commentary,
    text: "Texte \(item)"
  )
}
