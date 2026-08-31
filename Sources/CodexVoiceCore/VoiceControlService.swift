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
  private let pendingResponseCount: () -> Int
  private var lastSequenceByClientID: [String: UInt64] = [:]

  public init(
    authorizationToken: String,
    audio: VoiceAudioCoordinator,
    pendingResponseCount: @escaping () -> Int = { 0 }
  ) {
    self.authorizationToken = authorizationToken
    self.audio = audio
    self.pendingResponseCount = pendingResponseCount
  }

  public var state: VoiceControlState {
    VoiceControlState(audio: audio.snapshot, pendingResponseCount: pendingResponseCount())
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
    switch request.command.kind {
    case .getState:
      actionPerformed = false
    case .interruptAudio:
      actionPerformed = audio.interrupt()
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
      let previous = audio.settings.volume
      audio.setVolume(Float(volume))
      actionPerformed = previous != audio.settings.volume
    }

    lastSequenceByClientID[clientID] = request.sequence
    return VoiceControlHandlingResult(
      message: response(
        request,
        status: .ok,
        actionPerformed: actionPerformed,
        state: state
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
    error: VoiceControlErrorPayload? = nil
  ) -> VoiceControlMessage {
    VoiceControlMessage(
      kind: .response,
      clientID: request.clientID,
      sequence: request.sequence,
      status: status,
      actionPerformed: actionPerformed,
      state: state,
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
