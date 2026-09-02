import Foundation
import XCTest

@testable import CodexVoiceCore

@MainActor
final class VoiceControlServiceTests: XCTestCase {
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
    XCTAssertEqual(try JSONDecoder().decode(VoiceControlRequest.self, from: voiceData), voiceRequest)
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
    XCTAssertEqual(fixture.coordinator.settings.volume, 0.7)
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
}

@MainActor
private func makeFixture(
  enabled: Bool = false,
  pendingResponseCount: Int = 0,
  mainConversation: VoiceControlConversation? = nil
) -> (
  service: VoiceControlService,
  coordinator: VoiceAudioCoordinator,
  driver: ControlFakeSpeechDriver
) {
  let driver = ControlFakeSpeechDriver()
  let coordinator = VoiceAudioCoordinator(
    driver: driver,
    defaultSettings: VoiceAudioSettings(isEnabled: enabled)
  )
  let service = VoiceControlService(
    authorizationToken: token,
    audio: coordinator,
    pendingResponseCount: { pendingResponseCount },
    mainConversation: { mainConversation },
    availableVoices: { testVoices }
  )
  return (service, coordinator, driver)
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
