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
  case history
  case notification
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
  public let latestTurnID: String?
  public let lastActivity: Date?
  public let hasTranscript: Bool

  public init(
    threadID: String,
    title: String?,
    latestUserTurnID: String?,
    pendingResponseCount: Int,
    latestTurnID: String? = nil,
    lastActivity: Date? = nil,
    hasTranscript: Bool = false
  ) {
    self.threadID = threadID
    self.title = title
    self.latestUserTurnID = latestUserTurnID
    self.pendingResponseCount = pendingResponseCount
    self.latestTurnID = latestTurnID ?? latestUserTurnID
    self.lastActivity = lastActivity
    self.hasTranscript = hasTranscript
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
      messagesByID[message.itemID] = CodexAssistantMessage(
        threadID: message.threadID,
        turnID: message.turnID, itemID: message.itemID, phase: message.phase,
        text: String(message.text.prefix(65_536)))
      while messageOrder.count > 8 { messagesByID[messageOrder.removeFirst()] = nil }
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
    var latestTurnID: String?
    var lastActivity: Date?
    var hasTranscript = false
    var turns: [String: TurnState] = [:]
  }

  private struct PendingMarker {
    let key: TurnKey
    let readyAt: Date?
  }

  private var threads: [String: ThreadState] = [:]
  private var titles: [String: String] = [:]
  private var titleIdentities = BoundedIdentitySet(capacity: 2_048)
  private var pendingMarkers: [PendingMarker] = []
  private var pendingKeys: Set<TurnKey> = []
  private var dispatchedItemKeys = BoundedIdentitySet()
  private var handledLiveIdentities = BoundedIdentitySet()
  private var mainSelectionTimestamp: Date?

  public private(set) var mainConversation: VoiceConversationReference?

  public init() {}

  public var snapshot: VoiceOrchestratorSnapshot {
    let pending = pendingMarkers.compactMap(makePendingResponse)
    let threadSnapshots = threads.map { threadID, state in
      VoiceThreadSnapshot(
        threadID: threadID,
        title: state.title ?? titles[threadID],
        latestUserTurnID: state.latestUserTurnID,
        pendingResponseCount: pending.filter { $0.threadID == threadID }.count,
        latestTurnID: state.latestTurnID,
        lastActivity: state.lastActivity,
        hasTranscript: state.hasTranscript
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
    if observed.origin == .transcriptHistory { handledLiveIdentities.insert(observed.identityKey) }
    let isLiveObservation =
      observed.origin != .appServerSnapshot
      && observed.origin != .sessionIndex
      && observed.origin != .transcriptHistory
      && handledLiveIdentities.insert(observed.identityKey).inserted

    // Rehydrate bounded state even if the canonical merger already knows this
    // historical identity (or a higher-authority title came from the index).
    guard ingestion.stateChanged || isLiveObservation || observed.origin == .transcriptHistory
    else { return [] }
    applyState(from: canonical.payload)
    if observed.origin != .sessionIndex {
      threads[canonical.payload.threadID]?.hasTranscript = true
    }
    if let timestamp = canonical.timestamp {
      let previous = threads[canonical.payload.threadID]?.lastActivity ?? .distantPast
      threads[canonical.payload.threadID]?.lastActivity = max(previous, timestamp)
    }
    trimState(keeping: canonical.payload.threadID)
    guard isLiveObservation else { return [] }

    switch canonical.payload {
    case .userMessageCompleted(let message):
      return selectMainConversation(for: message, timestamp: observed.timestamp)
    case .assistantMessageCompleted(let message):
      return routeNewMessage(message)
    case .turnCompleted(let completion):
      return routeCompletedTurn(completion, timestamp: observed.timestamp)
    case .turnStarted(let turn):
      if let timestamp = observed.timestamp, let selectedAt = mainSelectionTimestamp,
        timestamp < selectedAt
      {
        return []
      }
      if mainConversation?.threadID == turn.threadID {
        let previous = mainConversation
        let next = VoiceConversationReference(threadID: turn.threadID, turnID: turn.turnID)
        mainConversation = next
        return previous == next
          ? [] : [.mainConversationChanged(.init(previous: previous, current: next))]
      }
      return []
    case .threadObserved:
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
      if let title = metadata.title {
        state.title = String(title.prefix(512))
        if let evicted = titleIdentities.insert(metadata.threadID).evicted { titles[evicted] = nil }
        titles[metadata.threadID] = state.title
      }
      threads[metadata.threadID] = state
    case .turnStarted(let turn):
      var state = threads[turn.threadID] ?? ThreadState()
      state.latestTurnID = turn.turnID
      if state.turns[turn.turnID] == nil { state.turns[turn.turnID] = TurnState() }
      threads[turn.threadID] = state
    case .userMessageCompleted(let message):
      var state = threads[message.threadID] ?? ThreadState()
      state.latestUserTurnID = message.turnID
      state.latestTurnID = message.turnID
      var turn = state.turns[message.turnID] ?? TurnState()
      turn.latestUserItemID = message.itemID
      state.turns[message.turnID] = turn
      threads[message.threadID] = state
    case .assistantMessageCompleted(let message):
      var state = threads[message.threadID] ?? ThreadState()
      if state.latestTurnID == nil { state.latestTurnID = message.turnID }
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

  /// Local routing only: does not send a message to Codex or cancel an agent.
  public func selectMainConversation(threadID: String, at date: Date = Date())
    -> [VoiceOrchestratorEffect]?
  {
    guard let state = threads[threadID], state.hasTranscript || state.latestTurnID != nil else {
      return nil
    }
    // An observed journal may have only tool output in its bounded tail. Select
    // the task now; bind its turn when its next live message/lifecycle arrives.
    let turnID = state.latestTurnID ?? ""
    let previous = mainConversation
    let next = VoiceConversationReference(threadID: threadID, turnID: turnID)
    mainConversation = next
    mainSelectionTimestamp = date
    var effects: [VoiceOrchestratorEffect] = []
    if previous != next {
      effects.append(.mainConversationChanged(.init(previous: previous, current: next)))
    }
    let count = clearPendingResponses(for: threadID)
    if count > 0 {
      effects.append(.pendingResponsesCleared(.init(threadID: threadID, count: count)))
    }
    return effects
  }

  public func discardPendingResponses() {
    pendingMarkers.removeAll(keepingCapacity: true)
    pendingKeys.removeAll(keepingCapacity: true)
  }

  private func trimState(keeping threadID: String) {
    if var state = threads[threadID], state.turns.count > 6 {
      // Turn insertion order is not exposed by Dictionary. Protect the latest
      // interaction and pending completions; remove only inactive contexts.
      let protected = Set(
        [
          state.latestTurnID, state.latestUserTurnID,
          mainConversation?.threadID == threadID ? mainConversation?.turnID : nil,
        ].compactMap { $0 }
      )
      .union(pendingMarkers.filter { $0.key.threadID == threadID }.map { $0.key.turnID })
      for key in state.turns.keys.sorted() where state.turns.count > 6 && !protected.contains(key) {
        state.turns[key] = nil
      }
      threads[threadID] = state
    }
    if threads.count > 128 {
      let oldest = threads.filter { $0.key != threadID && $0.key != mainConversation?.threadID }
        .min {
          if $0.value.hasTranscript != $1.value.hasTranscript { return !$0.value.hasTranscript }
          return ($0.value.lastActivity ?? .distantPast) < ($1.value.lastActivity ?? .distantPast)
        }?
        .key
      if let oldest {
        threads[oldest] = nil
        _ = clearPendingResponses(for: oldest)
      }
    }
    if pendingMarkers.count > 64 {
      let removed = pendingMarkers.removeFirst()
      pendingKeys.remove(removed.key)
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
    if mainConversation?.threadID == message.threadID, mainConversation?.turnID == "" {
      mainConversation = conversation
    }
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
          threadTitle: threads[message.threadID]?.title ?? titles[message.threadID],
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
      threadTitle: threads[marker.key.threadID]?.title ?? titles[marker.key.threadID],
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
