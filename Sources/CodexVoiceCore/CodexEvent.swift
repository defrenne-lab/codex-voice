import Foundation

public enum CodexEventOrigin: String, Sendable {
  case jsonlLifecycle
  case jsonlCompletedItem
  case jsonlResponseItem
  /// Bounded historical context, never a trigger for automatic speech.
  case transcriptHistory
  case sessionIndex
  case appServerSnapshot
}

public enum CodexEventAuthority: Int, Comparable, Sendable {
  case jsonlFallback = 10
  case jsonlCompleted = 20
  case sessionIndex = 25
  case appServerSnapshot = 30

  public static func < (lhs: Self, rhs: Self) -> Bool {
    lhs.rawValue < rhs.rawValue
  }
}

public enum CodexMessagePhase: Equatable, Sendable {
  case commentary
  case finalAnswer
  case unknown(String?)

  public init(rawValue: String?) {
    switch rawValue {
    case "commentary": self = .commentary
    case "final_answer", "finalAnswer": self = .finalAnswer
    default: self = .unknown(rawValue)
    }
  }

  public var rawValue: String? {
    switch self {
    case .commentary: return "commentary"
    case .finalAnswer: return "final_answer"
    case .unknown(let value): return value
    }
  }
}

public struct CodexThreadMetadata: Equatable, Sendable {
  public let threadID: String
  public let title: String?
  public let isSubagent: Bool

  public init(threadID: String, title: String?, isSubagent: Bool) {
    self.threadID = threadID
    self.title = title
    self.isSubagent = isSubagent
  }
}

public struct CodexTurnReference: Equatable, Sendable {
  public let threadID: String
  public let turnID: String

  public init(threadID: String, turnID: String) {
    self.threadID = threadID
    self.turnID = turnID
  }
}

public struct CodexUserMessageReference: Equatable, Sendable {
  public let threadID: String
  public let turnID: String
  public let itemID: String

  public init(threadID: String, turnID: String, itemID: String) {
    self.threadID = threadID
    self.turnID = turnID
    self.itemID = itemID
  }
}

public struct CodexAssistantMessage: Equatable, Sendable {
  public let threadID: String
  public let turnID: String
  public let itemID: String
  public let phase: CodexMessagePhase
  public let text: String

  public init(
    threadID: String,
    turnID: String,
    itemID: String,
    phase: CodexMessagePhase,
    text: String
  ) {
    self.threadID = threadID
    self.turnID = turnID
    self.itemID = itemID
    self.phase = phase
    self.text = text
  }
}

public struct CodexTurnCompletion: Equatable, Sendable {
  public let threadID: String
  public let turnID: String
  public let status: String

  public init(threadID: String, turnID: String, status: String) {
    self.threadID = threadID
    self.turnID = turnID
    self.status = status
  }
}

public enum CodexEventPayload: Equatable, Sendable {
  case threadObserved(CodexThreadMetadata)
  case turnStarted(CodexTurnReference)
  case userMessageCompleted(CodexUserMessageReference)
  case assistantMessageCompleted(CodexAssistantMessage)
  case turnCompleted(CodexTurnCompletion)

  public var threadID: String {
    switch self {
    case .threadObserved(let value): return value.threadID
    case .turnStarted(let value): return value.threadID
    case .userMessageCompleted(let value): return value.threadID
    case .assistantMessageCompleted(let value): return value.threadID
    case .turnCompleted(let value): return value.threadID
    }
  }

  public var identityKey: String {
    switch self {
    case .threadObserved(let value):
      return "thread|\(value.threadID)"
    case .turnStarted(let value):
      return "turn|\(value.threadID)|\(value.turnID)|started"
    case .userMessageCompleted(let value):
      return "item|\(value.threadID)|\(value.turnID)|\(value.itemID)"
    case .assistantMessageCompleted(let value):
      return "item|\(value.threadID)|\(value.turnID)|\(value.itemID)"
    case .turnCompleted(let value):
      return "turn|\(value.threadID)|\(value.turnID)|completed"
    }
  }
}

public struct CodexSourceEvent: Equatable, Sendable {
  public let timestamp: Date?
  public let origin: CodexEventOrigin
  public let authority: CodexEventAuthority
  public let payload: CodexEventPayload

  public init(
    timestamp: Date?,
    origin: CodexEventOrigin,
    authority: CodexEventAuthority,
    payload: CodexEventPayload
  ) {
    self.timestamp = timestamp
    self.origin = origin
    self.authority = authority
    self.payload = payload
  }

  public var identityKey: String { payload.identityKey }
}

public struct CodexIngestionDiagnostic: Equatable, Sendable {
  public let file: String?
  public let message: String

  public init(file: String? = nil, message: String) {
    self.file = file
    self.message = message
  }
}

public struct CodexEventBatch: Sendable {
  public var events: [CodexSourceEvent]
  public var diagnostics: [CodexIngestionDiagnostic]

  public init(
    events: [CodexSourceEvent] = [],
    diagnostics: [CodexIngestionDiagnostic] = []
  ) {
    self.events = events
    self.diagnostics = diagnostics
  }
}
