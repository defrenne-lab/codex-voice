import Foundation

public enum VoiceControlProtocol {
  public static let version = 1
  public static let webSocketSubprotocol = "codex-voice.v1"
  public static let defaultPort: UInt16 = 48_731
  public static let maximumMessageBytes = 64 * 1_024
}

public enum VoiceControlCommandKind: String, Codable, Sendable {
  case getState
  case interruptAudio
  case setVoiceEnabled
  case setMuted
  case setVolume
  case setRate
  case setVoiceIdentifier
}

public struct VoiceControlCommand: Codable, Equatable, Sendable {
  public let kind: VoiceControlCommandKind
  public let booleanValue: Bool?
  public let numberValue: Double?
  public let stringValue: String?

  public init(
    kind: VoiceControlCommandKind,
    booleanValue: Bool? = nil,
    numberValue: Double? = nil,
    stringValue: String? = nil
  ) {
    self.kind = kind
    self.booleanValue = booleanValue
    self.numberValue = numberValue
    self.stringValue = stringValue
  }

  public static let getState = VoiceControlCommand(kind: .getState)
  public static let interruptAudio = VoiceControlCommand(kind: .interruptAudio)

  public static func setVoiceEnabled(_ enabled: Bool) -> VoiceControlCommand {
    VoiceControlCommand(kind: .setVoiceEnabled, booleanValue: enabled)
  }

  public static func setMuted(_ muted: Bool) -> VoiceControlCommand {
    VoiceControlCommand(kind: .setMuted, booleanValue: muted)
  }

  public static func setVolume(_ volume: Double) -> VoiceControlCommand {
    VoiceControlCommand(kind: .setVolume, numberValue: volume)
  }

  public static func setRate(_ rate: Double) -> VoiceControlCommand {
    VoiceControlCommand(kind: .setRate, numberValue: rate)
  }

  public static func setVoiceIdentifier(_ identifier: String?) -> VoiceControlCommand {
    VoiceControlCommand(kind: .setVoiceIdentifier, stringValue: identifier ?? "")
  }
}

public struct VoiceControlRequest: Codable, Equatable, Sendable {
  public let version: Int
  public let clientID: String
  public let sequence: UInt64
  public let authorization: String
  public let command: VoiceControlCommand

  public init(
    version: Int = VoiceControlProtocol.version,
    clientID: String,
    sequence: UInt64,
    authorization: String,
    command: VoiceControlCommand
  ) {
    self.version = version
    self.clientID = clientID
    self.sequence = sequence
    self.authorization = authorization
    self.command = command
  }
}

public struct VoiceControlCurrentAudio: Codable, Equatable, Sendable {
  public let unitID: String
  public let threadID: String
  public let turnID: String
  public let threadTitle: String?
  public let kind: String

  public init(unit: VoiceAudioUnit) {
    unitID = unit.id
    threadID = unit.threadID
    turnID = unit.turnID
    threadTitle = unit.threadTitle
    kind = unit.kind.rawValue
  }
}

public struct VoiceControlVoice: Codable, Equatable, Identifiable, Sendable {
  public let identifier: String
  public let name: String
  public let language: String

  public var id: String { identifier }

  public init(identifier: String, name: String, language: String) {
    self.identifier = identifier
    self.name = name
    self.language = language
  }
}

public struct VoiceControlState: Codable, Equatable, Sendable {
  public let voiceEnabled: Bool
  public let muted: Bool
  public let volume: Float
  public let rate: Float
  public let voiceIdentifier: String?
  public let availableVoices: [VoiceControlVoice]?
  public let currentAudio: VoiceControlCurrentAudio?
  public let queuedUnitCount: Int
  public let pendingResponseCount: Int

  public init(
    audio: VoiceAudioSnapshot,
    pendingResponseCount: Int,
    availableVoices: [VoiceControlVoice] = []
  ) {
    voiceEnabled = audio.settings.isEnabled
    muted = audio.settings.isMuted
    volume = audio.settings.volume
    rate = audio.settings.rate
    voiceIdentifier = audio.settings.voiceIdentifier
    self.availableVoices = availableVoices
    currentAudio = audio.currentUnit.map(VoiceControlCurrentAudio.init)
    queuedUnitCount = audio.queuedUnitCount
    self.pendingResponseCount = max(0, pendingResponseCount)
  }
}

public enum VoiceControlMessageKind: String, Codable, Sendable {
  case response
  case stateChanged
}

public enum VoiceControlResponseStatus: String, Codable, Sendable {
  case ok
  case duplicate
  case rejected
}

public struct VoiceControlErrorPayload: Codable, Equatable, Sendable {
  public let code: String
  public let message: String

  public init(code: String, message: String) {
    self.code = code
    self.message = message
  }
}

public struct VoiceControlMessage: Codable, Equatable, Sendable {
  public let version: Int
  public let kind: VoiceControlMessageKind
  public let clientID: String?
  public let sequence: UInt64?
  public let status: VoiceControlResponseStatus?
  public let actionPerformed: Bool?
  public let state: VoiceControlState?
  public let error: VoiceControlErrorPayload?

  public init(
    version: Int = VoiceControlProtocol.version,
    kind: VoiceControlMessageKind,
    clientID: String? = nil,
    sequence: UInt64? = nil,
    status: VoiceControlResponseStatus? = nil,
    actionPerformed: Bool? = nil,
    state: VoiceControlState? = nil,
    error: VoiceControlErrorPayload? = nil
  ) {
    self.version = version
    self.kind = kind
    self.clientID = clientID
    self.sequence = sequence
    self.status = status
    self.actionPerformed = actionPerformed
    self.state = state
    self.error = error
  }
}
