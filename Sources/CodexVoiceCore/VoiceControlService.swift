import Foundation

public struct VoiceControlHandlingResult: Equatable, Sendable {
  public let message: VoiceControlMessage
  public let isAuthenticated: Bool

  public init(message: VoiceControlMessage, isAuthenticated: Bool) {
    self.message = message
    self.isAuthenticated = isAuthenticated
  }
}

@MainActor
public final class VoiceControlService {
  private let authorizationToken: String
  private let audio: VoiceAudioCoordinator
  private let systemVolume: VoiceSystemVolumeControlling
  private let pronunciationDictionary: VoicePronunciationDictionaryManaging
  private let pendingResponseCount: () -> Int
  private let mainConversation: () -> VoiceControlConversation?
  private let availableVoices: () -> [VoiceControlVoice]
  private let readingSession: VoiceReadingSession?
  private var lastSequenceByClientID: [String: UInt64] = [:]

  public init(
    authorizationToken: String,
    audio: VoiceAudioCoordinator,
    systemVolume: VoiceSystemVolumeControlling,
    pronunciationDictionary: VoicePronunciationDictionaryManaging,
    pendingResponseCount: @escaping () -> Int = { 0 },
    mainConversation: @escaping () -> VoiceControlConversation? = { nil },
    availableVoices: @escaping () -> [VoiceControlVoice] = { [] },
    readingSession: VoiceReadingSession? = nil
  ) {
    self.authorizationToken = authorizationToken
    self.audio = audio
    self.systemVolume = systemVolume
    self.pronunciationDictionary = pronunciationDictionary
    self.pendingResponseCount = pendingResponseCount
    self.mainConversation = mainConversation
    self.availableVoices = availableVoices
    self.readingSession = readingSession
  }

  public var state: VoiceControlState {
    VoiceControlState(
      audio: audio.snapshot,
      systemVolume: systemVolume.volume,
      pendingResponseCount: readingSession?.pendingNotificationCount ?? pendingResponseCount(),
      mainConversation: readingSession?.mainConversation ?? mainConversation(),
      availableVoices: availableVoices(),
      conversations: readingSession?.conversations,
      history: readingSession?.navigation
    )
  }

  public func stateChangedMessage() -> VoiceControlMessage {
    VoiceControlMessage(kind: .stateChanged, state: state)
  }

  public func handle(_ request: VoiceControlRequest) -> VoiceControlHandlingResult {
    guard request.version == VoiceControlProtocol.version else {
      return rejected(
        request,
        code: "unsupportedVersion",
        message: "Version de protocole non prise en charge.",
        authenticated: false
      )
    }
    guard constantTimeEquals(request.authorization, authorizationToken) else {
      return rejected(
        request,
        code: "unauthorized",
        message: "Authentification refusée.",
        authenticated: false
      )
    }

    let clientID = request.clientID.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clientID.isEmpty, clientID.utf8.count <= 128 else {
      return rejected(
        request,
        code: "invalidClientID",
        message: "Identifiant client absent ou trop long.",
        authenticated: true
      )
    }
    guard request.sequence > 0 else {
      return rejected(
        request,
        code: "invalidSequence",
        message: "La séquence doit être strictement positive.",
        authenticated: true
      )
    }
    if let lastSequence = lastSequenceByClientID[clientID], request.sequence <= lastSequence {
      return VoiceControlHandlingResult(
        message: response(
          request,
          status: .duplicate,
          actionPerformed: false,
          state: state
        ),
        isAuthenticated: true
      )
    }

    let actionPerformed: Bool
    var pronunciationDictionaryPayload: VoiceControlPronunciationDictionary?
    switch request.command.kind {
    case .getState:
      actionPerformed = false
    case .interruptAudio:
      actionPerformed = readingSession?.interrupt() ?? audio.interrupt()
    case .selectConversation:
      guard let readingSession else {
        return rejected(
          request, code: "featureUnavailable", message: "Mettre à jour le service du Mac mini.",
          authenticated: true)
      }
      guard let threadID = request.command.stringValue, !threadID.isEmpty,
        threadID.utf8.count <= 512,
        readingSession.selectConversation(threadID)
      else { return invalidPayload(request, expected: "une conversation récente connue") }
      actionPerformed = true
    case .previousBlock, .nextBlock:
      guard let readingSession else {
        return rejected(
          request, code: "featureUnavailable", message: "Mettre à jour le service du Mac mini.",
          authenticated: true)
      }
      actionPerformed = readingSession.navigate(forward: request.command.kind == .nextBlock)
    case .setVoiceEnabled:
      guard let enabled = request.command.booleanValue else {
        return invalidPayload(request, expected: "booleanValue")
      }
      let previous = audio.settings.isEnabled
      audio.setVoiceEnabled(enabled)
      actionPerformed = previous != audio.settings.isEnabled
    case .setMuted:
      guard let muted = request.command.booleanValue else {
        return invalidPayload(request, expected: "booleanValue")
      }
      let previous = audio.settings.isMuted
      audio.setMuted(muted)
      actionPerformed = previous != audio.settings.isMuted
    case .setVolume:
      guard let volume = request.command.numberValue, volume.isFinite, (0...1).contains(volume)
      else {
        return invalidPayload(request, expected: "numberValue entre 0 et 1")
      }
      let previous = systemVolume.volume
      guard systemVolume.setVolume(Float(volume)) else {
        return rejected(
          request,
          code: "systemVolumeUnavailable",
          message: "Le volume système du périphérique de sortie ne peut pas être modifié.",
          authenticated: true
        )
      }
      actionPerformed = abs(previous - systemVolume.volume) > 0.0001
    case .setRate:
      guard let rate = request.command.numberValue, rate.isFinite, (0.1...1).contains(rate)
      else {
        return invalidPayload(request, expected: "numberValue entre 0,1 et 1")
      }
      let previous = audio.settings.rate
      audio.setRate(Float(rate))
      actionPerformed = previous != audio.settings.rate
    case .setVoiceIdentifier:
      guard let rawIdentifier = request.command.stringValue,
        rawIdentifier.utf8.count <= 512
      else {
        return invalidPayload(request, expected: "stringValue")
      }
      let identifier = rawIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
      guard identifier.isEmpty || availableVoices().contains(where: { $0.identifier == identifier })
      else {
        return invalidPayload(request, expected: "identifiant d'une voix installée")
      }
      let previous = audio.settings.voiceIdentifier
      audio.setVoiceIdentifier(identifier)
      actionPerformed = previous != audio.settings.voiceIdentifier
    case .getPronunciationDictionary:
      do {
        pronunciationDictionaryPayload = VoiceControlPronunciationDictionary(
          content: try pronunciationDictionary.loadContent()
        )
      } catch {
        return rejected(
          request,
          code: "pronunciationDictionaryUnavailable",
          message: error.localizedDescription,
          authenticated: true
        )
      }
      actionPerformed = false
    case .setPronunciationDictionary:
      guard let content = request.command.stringValue,
        content.utf8.count <= VoiceControlProtocol.maximumPronunciationDictionaryBytes
      else {
        return invalidPayload(
          request,
          expected: "un dictionnaire UTF-8 de moins de 32 Kio"
        )
      }
      do {
        let previous = try pronunciationDictionary.loadContent()
        try pronunciationDictionary.replaceContent(content)
        pronunciationDictionaryPayload = VoiceControlPronunciationDictionary(content: content)
        actionPerformed = previous != content
      } catch {
        return rejected(
          request,
          code: "invalidPronunciationDictionary",
          message: error.localizedDescription,
          authenticated: true
        )
      }
    }

    lastSequenceByClientID[clientID] = request.sequence
    return VoiceControlHandlingResult(
      message: response(
        request,
        status: .ok,
        actionPerformed: actionPerformed,
        state: state,
        pronunciationDictionary: pronunciationDictionaryPayload
      ),
      isAuthenticated: true
    )
  }

  private func invalidPayload(
    _ request: VoiceControlRequest,
    expected: String
  ) -> VoiceControlHandlingResult {
    rejected(
      request,
      code: "invalidPayload",
      message: "La commande attend \(expected).",
      authenticated: true
    )
  }

  private func rejected(
    _ request: VoiceControlRequest,
    code: String,
    message: String,
    authenticated: Bool
  ) -> VoiceControlHandlingResult {
    VoiceControlHandlingResult(
      message: response(
        request,
        status: .rejected,
        state: authenticated ? state : nil,
        error: VoiceControlErrorPayload(code: code, message: message)
      ),
      isAuthenticated: authenticated
    )
  }

  private func response(
    _ request: VoiceControlRequest,
    status: VoiceControlResponseStatus,
    actionPerformed: Bool? = nil,
    state: VoiceControlState? = nil,
    pronunciationDictionary: VoiceControlPronunciationDictionary? = nil,
    error: VoiceControlErrorPayload? = nil
  ) -> VoiceControlMessage {
    VoiceControlMessage(
      kind: .response,
      clientID: request.clientID,
      sequence: request.sequence,
      status: status,
      actionPerformed: actionPerformed,
      state: state,
      pronunciationDictionary: pronunciationDictionary,
      error: error
    )
  }
}

private func constantTimeEquals(_ lhs: String, _ rhs: String) -> Bool {
  let left = Array(lhs.utf8)
  let right = Array(rhs.utf8)
  guard left.count == right.count else { return false }
  var difference: UInt8 = 0
  for index in left.indices {
    difference |= left[index] ^ right[index]
  }
  return difference == 0
}
