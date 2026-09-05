import Foundation
import XCTest

@testable import CodexVoiceCore

@MainActor
final class VoiceControlServiceTests: XCTestCase {
  func testSelectionAndHistoryAreAuthenticatedAndDoNotLeakMessageTextInState() throws {
    let driver = ControlFakeSpeechDriver()
    let audio = VoiceAudioCoordinator(driver: driver, defaultSettings: .init(isEnabled: true))
    let reading = VoiceReadingSession(audio: audio)
    let composite = CompositeCodexEventSource()
    reading.process(
      composite.ingest(
        .init(
          timestamp: nil, origin: .transcriptHistory,
          authority: .jsonlCompleted,
          payload: .assistantMessageCompleted(
            .init(
              threadID: "recent", turnID: "turn", itemID: "message", phase: .finalAnswer,
              text: "Texte privé non transmis dans l’état.")))))
    let service = VoiceControlService(
      authorizationToken: token, audio: audio,
      systemVolume: ControlFakeSystemVolume(),
      pronunciationDictionary: ControlFakePronunciationDictionary(content: "source,replacement\n"),
      readingSession: reading)
    let denied = service.handle(
      request(sequence: 1, authorization: "wrong", command: .selectConversation("recent")))
    XCTAssertEqual(denied.message.status, .rejected)
    XCTAssertNil(reading.mainConversation)
    let selected = service.handle(request(sequence: 2, command: .selectConversation("recent")))
    XCTAssertEqual(selected.message.state?.mainConversation?.threadID, "recent")
    XCTAssertTrue(driver.requests.isEmpty)
    let replayed = service.handle(request(sequence: 3, command: .previousBlock))
    XCTAssertEqual(replayed.message.actionPerformed, true)
    XCTAssertEqual(driver.requests.last?.text, "Texte privé non transmis dans l’état.")
    let count = driver.requests.count
    XCTAssertEqual(
      service.handle(request(sequence: 3, command: .previousBlock)).message.status, .duplicate)
    XCTAssertEqual(driver.requests.count, count)
    let wire = String(
      decoding: try JSONEncoder().encode(service.stateChangedMessage()), as: UTF8.self)
    XCTAssertFalse(wire.contains("Texte privé"))
    XCTAssertFalse(wire.contains(token))
    XCTAssertLessThan(wire.utf8.count, VoiceControlProtocol.maximumMessageBytes)
    XCTAssertEqual(
      service.handle(request(sequence: 4, command: .selectConversation("absent"))).message.status,
      .rejected)
  }

  func testOldStateDecodesWithoutHistoryAndMissingSessionRejectsNewCommandsClearly() throws {
    let fixture = makeFixture()
    var state = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(fixture.service.state))
        as? [String: Any])
    state.removeValue(forKey: "conversations")
    state.removeValue(forKey: "history")
    let decoded = try JSONDecoder().decode(
      VoiceControlState.self, from: JSONSerialization.data(withJSONObject: state))
    XCTAssertNil(decoded.conversations)
    XCTAssertNil(decoded.history)
    XCTAssertEqual(
      fixture.service.handle(request(sequence: 1, command: .previousBlock)).message.error?.code,
      "featureUnavailable")
  }

  func testProtocolRequestRoundTripsThroughJSON() throws {
    let request = VoiceControlRequest(
      clientID: "macbook",
      sequence: 42,
      authorization: token,
      command: .setVolume(0.35)
    )

    let data = try JSONEncoder().encode(request)
    XCTAssertEqual(try JSONDecoder().decode(VoiceControlRequest.self, from: data), request)

    let voiceRequest = VoiceControlRequest(
      clientID: "macbook",
      sequence: 43,
      authorization: token,
      command: .setVoiceIdentifier(testVoices[1].identifier)
    )
    let voiceData = try JSONEncoder().encode(voiceRequest)
    XCTAssertEqual(
      try JSONDecoder().decode(VoiceControlRequest.self, from: voiceData), voiceRequest)
  }

  func testUnauthorizedRequestNeverExposesState() {
    let fixture = makeFixture()
    let result = fixture.service.handle(
      request(sequence: 1, authorization: "incorrect", command: .getState)
    )

    XCTAssertFalse(result.isAuthenticated)
    XCTAssertEqual(result.message.status, .rejected)
    XCTAssertEqual(result.message.error?.code, "unauthorized")
    XCTAssertNil(result.message.state)
  }

  func testCommandsMutateSettingsAndReturnCompleteState() throws {
    let fixture = makeFixture(pendingResponseCount: 3)

    let enabled = fixture.service.handle(
      request(sequence: 1, command: .setVoiceEnabled(true))
    )
    let volume = fixture.service.handle(request(sequence: 2, command: .setVolume(0.35)))
    let rate = fixture.service.handle(request(sequence: 3, command: .setRate(0.53)))
    let voice = fixture.service.handle(
      request(sequence: 4, command: .setVoiceIdentifier(testVoices[1].identifier))
    )
    let muted = fixture.service.handle(request(sequence: 5, command: .setMuted(true)))

    XCTAssertEqual(enabled.message.status, .ok)
    XCTAssertEqual(volume.message.state?.volume, 0.35)
    XCTAssertEqual(rate.message.state?.rate, 0.53)
    XCTAssertEqual(voice.message.state?.voiceIdentifier, testVoices[1].identifier)
    XCTAssertEqual(muted.message.state?.voiceEnabled, true)
    XCTAssertEqual(muted.message.state?.muted, true)
    XCTAssertEqual(muted.message.state?.pendingResponseCount, 3)
    XCTAssertEqual(muted.message.state?.availableVoices, testVoices)
    XCTAssertEqual(fixture.systemVolume.volume, 0.35)
  }

  func testRateAndVoiceCommandsRejectInvalidValues() {
    let fixture = makeFixture()

    let rate = fixture.service.handle(request(sequence: 1, command: .setRate(1.5)))
    let voice = fixture.service.handle(
      request(sequence: 2, command: .setVoiceIdentifier("missing-voice"))
    )

    XCTAssertEqual(rate.message.status, .rejected)
    XCTAssertEqual(voice.message.status, .rejected)
    XCTAssertEqual(fixture.coordinator.settings.rate, 0.48)
    XCTAssertNil(fixture.coordinator.settings.voiceIdentifier)
  }

  func testOlderSequenceIsAbsorbedWithoutApplyingCommand() {
    let fixture = makeFixture()
    _ = fixture.service.handle(request(sequence: 10, command: .setVolume(0.7)))

    let duplicate = fixture.service.handle(request(sequence: 9, command: .setVolume(0.1)))

    XCTAssertEqual(duplicate.message.status, .duplicate)
    XCTAssertEqual(duplicate.message.actionPerformed, false)
    XCTAssertEqual(fixture.systemVolume.volume, 0.7)
  }

  func testRemoteInterruptAbandonsCurrentUnitAndQueue() {
    let fixture = makeFixture(enabled: true)
    _ = fixture.coordinator.enqueue(controlUnit(item: "one"))
    _ = fixture.coordinator.enqueue(controlUnit(item: "two"))

    let result = fixture.service.handle(request(sequence: 1, command: .interruptAudio))

    XCTAssertEqual(result.message.status, .ok)
    XCTAssertEqual(result.message.actionPerformed, true)
    XCTAssertNil(result.message.state?.currentAudio)
    XCTAssertEqual(result.message.state?.queuedUnitCount, 0)
    XCTAssertEqual(fixture.driver.stopCalls, 1)
  }

  func testPublishedStateContainsMetadataButNeverSpokenText() throws {
    let fixture = makeFixture(enabled: true)
    _ = fixture.coordinator.enqueue(controlUnit(item: "one", text: "contenu confidentiel"))

    let message = fixture.service.stateChangedMessage()
    let json = String(decoding: try JSONEncoder().encode(message), as: UTF8.self)

    XCTAssertEqual(message.kind, .stateChanged)
    XCTAssertEqual(message.state?.currentAudio?.threadID, "thread-1")
    XCTAssertFalse(json.contains("contenu confidentiel"))
  }

  func testPublishedStateKeepsMainConversationWhileAudioIsIdle() {
    let mainConversation = VoiceControlConversation(
      threadID: "thread-main",
      turnID: "turn-main",
      threadTitle: "Améliorer la fusion"
    )
    let fixture = makeFixture(mainConversation: mainConversation)

    let state = fixture.service.state

    XCTAssertNil(state.currentAudio)
    XCTAssertEqual(state.mainConversation, mainConversation)
  }

  func testPronunciationDictionaryCanBeReadAndUpdated() {
    let fixture = makeFixture(dictionaryContent: "source,replacement\nGitHub,Guit-Heub\n")

    let read = fixture.service.handle(
      request(sequence: 1, command: .getPronunciationDictionary)
    )
    let updatedContent = "source,replacement\nShopify,shopifaille\n"
    let update = fixture.service.handle(
      request(sequence: 2, command: .setPronunciationDictionary(updatedContent))
    )

    XCTAssertEqual(
      read.message.pronunciationDictionary?.content,
      "source,replacement\nGitHub,Guit-Heub\n"
    )
    XCTAssertEqual(update.message.status, .ok)
    XCTAssertEqual(update.message.actionPerformed, true)
    XCTAssertEqual(fixture.dictionary.content, updatedContent)
  }

  func testUnauthorizedDictionaryRequestNeverExposesItsContent() throws {
    let fixture = makeFixture(dictionaryContent: "source,replacement\nSecret,private\n")
    let result = fixture.service.handle(
      request(
        sequence: 1,
        authorization: "incorrect",
        command: .getPronunciationDictionary
      )
    )
    let json = String(decoding: try JSONEncoder().encode(result.message), as: UTF8.self)

    XCTAssertFalse(result.isAuthenticated)
    XCTAssertNil(result.message.pronunciationDictionary)
    XCTAssertFalse(json.contains("Secret"))
  }

  func testSystemVolumeFailureRejectsCommandWithoutChangingReportedVolume() {
    let fixture = makeFixture()
    fixture.systemVolume.allowsChanges = false

    let result = fixture.service.handle(request(sequence: 1, command: .setVolume(0.2)))

    XCTAssertEqual(result.message.status, .rejected)
    XCTAssertEqual(result.message.error?.code, "systemVolumeUnavailable")
    XCTAssertEqual(fixture.service.state.volume, 0.8)
  }
}

@MainActor
private func makeFixture(
  enabled: Bool = false,
  pendingResponseCount: Int = 0,
  mainConversation: VoiceControlConversation? = nil,
  dictionaryContent: String = "source,replacement\n"
) -> (
  service: VoiceControlService,
  coordinator: VoiceAudioCoordinator,
  driver: ControlFakeSpeechDriver,
  systemVolume: ControlFakeSystemVolume,
  dictionary: ControlFakePronunciationDictionary
) {
  let driver = ControlFakeSpeechDriver()
  let systemVolume = ControlFakeSystemVolume()
  let dictionary = ControlFakePronunciationDictionary(content: dictionaryContent)
  let coordinator = VoiceAudioCoordinator(
    driver: driver,
    defaultSettings: VoiceAudioSettings(isEnabled: enabled)
  )
  let service = VoiceControlService(
    authorizationToken: token,
    audio: coordinator,
    systemVolume: systemVolume,
    pronunciationDictionary: dictionary,
    pendingResponseCount: { pendingResponseCount },
    mainConversation: { mainConversation },
    availableVoices: { testVoices }
  )
  return (service, coordinator, driver, systemVolume, dictionary)
}

private let token = String(repeating: "a", count: 64)
private let testVoices = [
  VoiceControlVoice(
    identifier: "com.apple.voice.compact.fr-FR.Thomas",
    name: "Thomas",
    language: "fr-FR"
  ),
  VoiceControlVoice(
    identifier: "com.apple.voice.enhanced.fr-FR.Aurelie",
    name: "Aurélie (Enhanced)",
    language: "fr-FR"
  ),
]

private func request(
  sequence: UInt64,
  authorization: String = token,
  command: VoiceControlCommand
) -> VoiceControlRequest {
  VoiceControlRequest(
    clientID: "macbook",
    sequence: sequence,
    authorization: authorization,
    command: command
  )
}

private func controlUnit(item: String, text: String = "Texte") -> VoiceAudioUnit {
  VoiceAudioUnit(
    id: "item|thread-1|turn-1|\(item)",
    groupID: "turn|thread-1|turn-1",
    threadID: "thread-1",
    turnID: "turn-1",
    itemID: item,
    threadTitle: "Conversation principale",
    kind: .commentary,
    text: text
  )
}

@MainActor
private final class ControlFakeSpeechDriver: VoiceSpeechDriver {
  var completionHandler: ((String, VoiceSpeechDriverOutcome) -> Void)?
  var requests: [VoiceSpeechDriverRequest] = []
  var stopCalls = 0

  func speak(_ request: VoiceSpeechDriverRequest) {
    requests.append(request)
  }

  func stop() {
    stopCalls += 1
  }
}

@MainActor
private final class ControlFakeSystemVolume: VoiceSystemVolumeControlling {
  var volume: Float = 0.8
  var allowsChanges = true

  func setVolume(_ volume: Float) -> Bool {
    guard allowsChanges else { return false }
    self.volume = min(1, max(0, volume))
    return true
  }
}

@MainActor
private final class ControlFakePronunciationDictionary: VoicePronunciationDictionaryManaging {
  var content: String

  init(content: String) {
    self.content = content
  }

  func loadContent() throws -> String { content }

  func replaceContent(_ content: String) throws {
    self.content = content
  }
}
