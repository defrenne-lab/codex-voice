import Foundation

public struct VoiceConversationReference: Equatable, Sendable {
  public let threadID: String
  public let turnID: String

  public init(threadID: String, turnID: String) {
    self.threadID = threadID
    self.turnID = turnID
  }
}

public struct VoiceMainConversationChange: Equatable, Sendable {
  public let previous: VoiceConversationReference?
  public let current: VoiceConversationReference

  public init(previous: VoiceConversationReference?, current: VoiceConversationReference) {
    self.previous = previous
    self.current = current
  }
}

public enum VoiceSpeechKind: String, Sendable {
  case commentary
  case finalAnswer
}

public struct VoiceSpeechRequest: Equatable, Sendable {
  public let groupID: String
  public let threadID: String
  public let turnID: String
  public let itemID: String
  public let threadTitle: String?
  public let kind: VoiceSpeechKind
  public let text: String

  public init(
    groupID: String? = nil,
    threadID: String,
    turnID: String,
    itemID: String,
    threadTitle: String?,
    kind: VoiceSpeechKind,
    text: String
  ) {
    self.groupID = groupID ?? "turn|\(threadID)|\(turnID)"
    self.threadID = threadID
    self.turnID = turnID
    self.itemID = itemID
    self.threadTitle = threadTitle
    self.kind = kind
    self.text = text
  }
}

public struct VoicePendingResponse: Equatable, Sendable {
  public let threadID: String
  public let turnID: String
  public let itemID: String
  public let threadTitle: String?
  public let text: String
  public let readyAt: Date?

  public init(
    threadID: String,
    turnID: String,
    itemID: String,
    threadTitle: String?,
    text: String,
    readyAt: Date?
  ) {
    self.threadID = threadID
    self.turnID = turnID
    self.itemID = itemID
    self.threadTitle = threadTitle
    self.text = text
    self.readyAt = readyAt
  }
}

public struct VoicePendingResponsesCleared: Equatable, Sendable {
  public let threadID: String
  public let count: Int

  public init(threadID: String, count: Int) {
    self.threadID = threadID
    self.count = count
  }
}

public enum VoiceOrchestratorEffect: Equatable, Sendable {
  case mainConversationChanged(VoiceMainConversationChange)
  case speechRequested(VoiceSpeechRequest)
  case parallelResponseReady(VoicePendingResponse)
  case pendingResponsesCleared(VoicePendingResponsesCleared)
}

public struct VoiceThreadSnapshot: Equatable, Sendable {
  public let threadID: String
  public let title: String?
  public let latestUserTurnID: String?
  public let pendingResponseCount: Int

  public init(
    threadID: String,
    title: String?,
    latestUserTurnID: String?,
    pendingResponseCount: Int
  ) {
    self.threadID = threadID
    self.title = title
    self.latestUserTurnID = latestUserTurnID
    self.pendingResponseCount = pendingResponseCount
  }
}

public struct VoiceOrchestratorSnapshot: Equatable, Sendable {
  public let mainConversation: VoiceConversationReference?
  public let threads: [VoiceThreadSnapshot]
  public let pendingResponses: [VoicePendingResponse]

  public init(
    mainConversation: VoiceConversationReference?,
    threads: [VoiceThreadSnapshot],
    pendingResponses: [VoicePendingResponse]
  ) {
    self.mainConversation = mainConversation
    self.threads = threads
    self.pendingResponses = pendingResponses
  }
}

public final class VoiceOrchestrator {
  private struct TurnKey: Hashable {
    let threadID: String
    let turnID: String
  }

  private struct TurnState {
    var status: String?
    var latestUserItemID: String?
    var messageOrder: [String] = []
    var messagesByID: [String: CodexAssistantMessage] = [:]

    mutating func store(_ message: CodexAssistantMessage) {
      if messagesByID[message.itemID] == nil { messageOrder.append(message.itemID) }
      messagesByID[message.itemID] = message
    }

    var finalCandidate: CodexAssistantMessage? {
      for itemID in messageOrder.reversed() {
        guard let message = messagesByID[itemID] else { continue }
        if message.phase == .finalAnswer { return message }
      }
      for itemID in messageOrder.reversed() {
        guard let message = messagesByID[itemID] else { continue }
        if case .unknown = message.phase { return message }
      }
      return nil
    }
  }

  private struct ThreadState {
    var title: String?
    var latestUserTurnID: String?
    var turns: [String: TurnState] = [:]
  }

  private struct PendingMarker {
    let key: TurnKey
    let readyAt: Date?
  }

  private var threads: [String: ThreadState] = [:]
  private var pendingMarkers: [PendingMarker] = []
  private var pendingKeys: Set<TurnKey> = []
  private var dispatchedItemKeys: Set<String> = []
  private var handledLiveIdentities: Set<String> = []
  private var mainSelectionTimestamp: Date?

  public private(set) var mainConversation: VoiceConversationReference?

  public init() {}

  public var snapshot: VoiceOrchestratorSnapshot {
    let pending = pendingMarkers.compactMap(makePendingResponse)
    let threadSnapshots = threads.map { threadID, state in
      VoiceThreadSnapshot(
        threadID: threadID,
        title: state.title,
        latestUserTurnID: state.latestUserTurnID,
        pendingResponseCount: pending.filter { $0.threadID == threadID }.count
      )
    }.sorted { $0.threadID < $1.threadID }
    return VoiceOrchestratorSnapshot(
      mainConversation: mainConversation,
      threads: threadSnapshots,
      pendingResponses: pending
    )
  }

  public func process(_ ingestion: CompositeIngestion) -> [VoiceOrchestratorEffect] {
    let canonical = ingestion.event
    let observed = ingestion.observation
    let isLiveObservation =
      observed.origin != .appServerSnapshot
      && observed.origin != .sessionIndex
      && handledLiveIdentities.insert(observed.identityKey).inserted

    guard ingestion.stateChanged || isLiveObservation else { return [] }
    applyState(from: canonical.payload)
    guard isLiveObservation else { return [] }

    switch canonical.payload {
    case .userMessageCompleted(let message):
      return selectMainConversation(for: message, timestamp: observed.timestamp)
    case .assistantMessageCompleted(let message):
      return routeNewMessage(message)
    case .turnCompleted(let completion):
      return routeCompletedTurn(completion, timestamp: observed.timestamp)
    case .threadObserved, .turnStarted:
      return []
    }
  }

  public func process(_ ingestions: [CompositeIngestion]) -> [VoiceOrchestratorEffect] {
    ingestions.flatMap(process)
  }

  private func applyState(from payload: CodexEventPayload) {
    switch payload {
    case .threadObserved(let metadata):
      var state = threads[metadata.threadID] ?? ThreadState()
      if let title = metadata.title { state.title = title }
      threads[metadata.threadID] = state
    case .turnStarted(let turn):
      var state = threads[turn.threadID] ?? ThreadState()
      if state.turns[turn.turnID] == nil { state.turns[turn.turnID] = TurnState() }
      threads[turn.threadID] = state
    case .userMessageCompleted(let message):
      var state = threads[message.threadID] ?? ThreadState()
      state.latestUserTurnID = message.turnID
      var turn = state.turns[message.turnID] ?? TurnState()
      turn.latestUserItemID = message.itemID
      state.turns[message.turnID] = turn
      threads[message.threadID] = state
    case .assistantMessageCompleted(let message):
      var state = threads[message.threadID] ?? ThreadState()
      var turn = state.turns[message.turnID] ?? TurnState()
      turn.store(message)
      state.turns[message.turnID] = turn
      threads[message.threadID] = state
    case .turnCompleted(let completion):
      var state = threads[completion.threadID] ?? ThreadState()
      var turn = state.turns[completion.turnID] ?? TurnState()
      turn.status = completion.status
      state.turns[completion.turnID] = turn
      threads[completion.threadID] = state
    }
  }

  private func selectMainConversation(
    for message: CodexUserMessageReference,
    timestamp: Date?
  ) -> [VoiceOrchestratorEffect] {
    if let timestamp, let mainSelectionTimestamp, timestamp < mainSelectionTimestamp {
      return []
    }
    let next = VoiceConversationReference(threadID: message.threadID, turnID: message.turnID)
    let previous = mainConversation
    mainConversation = next
    if let timestamp { mainSelectionTimestamp = timestamp }

    var effects: [VoiceOrchestratorEffect] = []
    if previous != next {
      effects.append(
        .mainConversationChanged(
          VoiceMainConversationChange(previous: previous, current: next)
        )
      )
    }

    let clearedCount = clearPendingResponses(for: message.threadID)
    if clearedCount > 0 {
      effects.append(
        .pendingResponsesCleared(
          VoicePendingResponsesCleared(threadID: message.threadID, count: clearedCount)
        )
      )
    }
    return effects
  }

  private func routeNewMessage(_ message: CodexAssistantMessage) -> [VoiceOrchestratorEffect] {
    let conversation = VoiceConversationReference(
      threadID: message.threadID,
      turnID: message.turnID
    )
    guard conversation == mainConversation else { return [] }

    switch message.phase {
    case .commentary:
      return requestSpeech(for: message, kind: .commentary)
    case .finalAnswer:
      return requestSpeech(for: message, kind: .finalAnswer)
    case .unknown:
      return []
    }
  }

  private func routeCompletedTurn(
    _ completion: CodexTurnCompletion,
    timestamp: Date?
  ) -> [VoiceOrchestratorEffect] {
    guard completion.status == "completed",
      let candidate = finalCandidate(threadID: completion.threadID, turnID: completion.turnID)
    else { return [] }

    if dispatchedItemKeys.contains(itemKey(candidate)) { return [] }

    let conversation = VoiceConversationReference(
      threadID: completion.threadID,
      turnID: completion.turnID
    )
    if conversation == mainConversation {
      return requestSpeech(for: candidate, kind: .finalAnswer)
    }

    let key = TurnKey(threadID: completion.threadID, turnID: completion.turnID)
    guard pendingKeys.insert(key).inserted else { return [] }
    pendingMarkers.append(PendingMarker(key: key, readyAt: timestamp))
    guard let response = makePendingResponse(pendingMarkers[pendingMarkers.count - 1]) else {
      return []
    }
    return [.parallelResponseReady(response)]
  }

  private func requestSpeech(
    for message: CodexAssistantMessage,
    kind: VoiceSpeechKind
  ) -> [VoiceOrchestratorEffect] {
    guard dispatchedItemKeys.insert(itemKey(message)).inserted else { return [] }
    return [
      .speechRequested(
        VoiceSpeechRequest(
          groupID: speechGroupID(for: message),
          threadID: message.threadID,
          turnID: message.turnID,
          itemID: message.itemID,
          threadTitle: threads[message.threadID]?.title,
          kind: kind,
          text: message.text
        )
      )
    ]
  }

  private func speechGroupID(for message: CodexAssistantMessage) -> String {
    let interactionID =
      threads[message.threadID]?.turns[message.turnID]?.latestUserItemID ?? message.turnID
    return "interaction|\(message.threadID)|\(message.turnID)|\(interactionID)"
  }

  private func finalCandidate(threadID: String, turnID: String) -> CodexAssistantMessage? {
    threads[threadID]?.turns[turnID]?.finalCandidate
  }

  private func makePendingResponse(_ marker: PendingMarker) -> VoicePendingResponse? {
    guard
      let message = finalCandidate(
        threadID: marker.key.threadID,
        turnID: marker.key.turnID
      )
    else { return nil }
    return VoicePendingResponse(
      threadID: marker.key.threadID,
      turnID: marker.key.turnID,
      itemID: message.itemID,
      threadTitle: threads[marker.key.threadID]?.title,
      text: message.text,
      readyAt: marker.readyAt
    )
  }

  private func clearPendingResponses(for threadID: String) -> Int {
    let removed = pendingMarkers.filter { $0.key.threadID == threadID }
    guard !removed.isEmpty else { return 0 }
    let removedKeys = Set(removed.map(\.key))
    pendingMarkers.removeAll { removedKeys.contains($0.key) }
    pendingKeys.subtract(removedKeys)
    return removed.count
  }

  private func itemKey(_ message: CodexAssistantMessage) -> String {
    "\(message.threadID)|\(message.turnID)|\(message.itemID)"
  }
}
