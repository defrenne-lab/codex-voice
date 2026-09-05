import Foundation

/// Coordinates the user's reading session. tick() is driven by the local poll
/// loop; tests inject a clock and never wait or produce real audio.
@MainActor
public final class VoiceReadingSession {
  public let orchestrator: VoiceOrchestrator
  public let history: VoiceRecentHistory
  private let audio: VoiceAudioCoordinator
  private let now: () -> Date
  private var pending: [VoicePendingResponse] = []
  private var batch: [VoicePendingResponse] = []
  private var batchID = UUID().uuidString
  private var nextNotificationAt = Date.distantPast
  private var lastForegroundActivity: Date
  private var activeUnit: VoiceAudioUnit?
  private var handledUserMessages = BoundedIdentitySet()
  private var lastInteractionAt: Date?
  public var eventHandler: ((VoiceAudioCoordinatorEvent) -> Void)?

  public init(
    audio: VoiceAudioCoordinator, orchestrator: VoiceOrchestrator = VoiceOrchestrator(),
    history: VoiceRecentHistory = VoiceRecentHistory(), now: @escaping () -> Date = Date.init
  ) {
    self.audio = audio
    self.orchestrator = orchestrator
    self.history = history
    self.now = now
    lastForegroundActivity = now()
    audio.eventHandler = { [weak self] event in self?.audioEvent(event) }
  }

  public var pendingNotificationCount: Int { pending.count + batch.count }

  public var mainConversation: VoiceControlConversation? {
    guard let main = orchestrator.mainConversation else { return nil }
    return VoiceControlConversation(
      threadID: main.threadID, turnID: main.turnID,
      threadTitle: orchestrator.snapshot.threads.first { $0.threadID == main.threadID }?.title
        .map { String($0.prefix(128)) })
  }

  public var conversations: [VoiceControlConversation] {
    orchestrator.snapshot.threads.filter {
      ($0.hasTranscript || $0.latestTurnID != nil)
        && $0.threadID.utf8.count <= 128 && ($0.latestTurnID?.utf8.count ?? 0) <= 128
    }
    .sorted {
      if $0.lastActivity != $1.lastActivity {
        return ($0.lastActivity ?? .distantPast) > ($1.lastActivity ?? .distantPast)
      }
      return $0.threadID < $1.threadID
    }.prefix(32).map {
      VoiceControlConversation(
        threadID: $0.threadID, turnID: $0.latestTurnID ?? "",
        threadTitle: $0.title.map { String($0.prefix(128)) })
    }
  }

  public var navigation: VoiceHistoryNavigationState {
    history.state(
      for: orchestrator.mainConversation?.threadID,
      liveBlockID: currentMainBlockID)
  }

  private var currentMainBlockID: String? {
    guard let unit = audio.snapshot.currentUnit,
      unit.threadID == orchestrator.mainConversation?.threadID, unit.kind != .history
    else { return nil }
    return unit.blockID
  }

  public func process(_ ingestion: CompositeIngestion) {
    if ingestion.stateChanged || ingestion.observation.origin == .transcriptHistory,
      case .assistantMessageCompleted(let message) = ingestion.event.payload
    {
      history.store(message)
    }
    if ingestion.stateChanged || ingestion.observation.origin == .transcriptHistory,
      case .turnCompleted(let turn) = ingestion.event.payload,
      turn.status == "completed"
    {
      history.finishTurn(threadID: turn.threadID, turnID: turn.turnID)
    }
    if case .userMessageCompleted = ingestion.event.payload,
      ![CodexEventOrigin.transcriptHistory, .appServerSnapshot, .sessionIndex].contains(
        ingestion.observation.origin),
      handledUserMessages.insert(ingestion.observation.identityKey).inserted
    {
      let timestamp = ingestion.observation.timestamp ?? now()
      if timestamp >= (lastInteractionAt ?? .distantPast) {
        lastInteractionAt = timestamp
        _ = interrupt()
      }
    }
    for effect in orchestrator.process(ingestion) { handle(effect) }
  }

  @discardableResult
  public func selectConversation(_ threadID: String) -> Bool {
    guard let effects = orchestrator.selectMainConversation(threadID: threadID, at: now()) else {
      return false
    }
    history.resetPosition(for: threadID)
    lastInteractionAt = now()
    for effect in effects { handle(effect) }
    lastForegroundActivity = now()
    return true
  }

  @discardableResult
  public func navigate(forward: Bool) -> Bool {
    guard audio.settings.isEnabled, !audio.settings.isMuted,
      let main = mainConversation,
      let block = history.navigate(
        threadID: main.threadID, forward: forward, liveBlockID: currentMainBlockID)
    else { return false }
    _ = interrupt()
    let id = UUID().uuidString
    let result = audio.enqueue(
      VoiceAudioUnit(
        id: "history|\(id)", groupID: "history|\(id)",
        threadID: block.threadID, turnID: block.turnID, itemID: block.itemID,
        threadTitle: main.threadTitle, kind: .history, text: block.text, blockID: block.id))
    return result == .started || result == .queued
  }

  @discardableResult
  public func interrupt() -> Bool {
    let hadNotifications = pendingNotificationCount > 0
    clearNotifications()
    lastForegroundActivity = now()
    return audio.interrupt() || hadNotifications
  }

  public func tick() {
    guard audio.settings.isEnabled, !audio.settings.isMuted else {
      clearNotifications()
      return
    }
    guard audio.snapshot.currentUnit == nil, audio.snapshot.queuedUnitCount == 0 else { return }
    let date = now()
    guard date.timeIntervalSince(lastForegroundActivity) >= 10 else { return }
    if batch.isEmpty {
      guard !pending.isEmpty else { return }
      batch = pending
      pending.removeAll(keepingCapacity: true)
      batchID = UUID().uuidString
    }
    guard date >= nextNotificationAt else { return }
    let response = batch.removeFirst()
    // A task selected since arrival is no longer an external notification.
    guard response.threadID != orchestrator.mainConversation?.threadID else { return }
    let title =
      orchestrator.snapshot.threads.first { $0.threadID == response.threadID }?.title
      ?? response.threadTitle
    let text =
      "\(VoiceReadableText.shortTitle(title)). \(VoiceReadableText.notificationSummary(response.text))"
    _ = audio.enqueue(
      VoiceAudioUnit(
        id: "notification|\(batchID)|\(response.threadID)|\(response.itemID)",
        groupID: "notifications|\(batchID)", threadID: response.threadID, turnID: response.turnID,
        itemID: response.itemID, threadTitle: title, kind: .notification, text: text,
        notificationCue: true))
    nextNotificationAt = .distantFuture
  }

  private func handle(_ effect: VoiceOrchestratorEffect) {
    switch effect {
    case .mainConversationChanged(let change):
      lastForegroundActivity = now()
      history.resetPosition(for: change.current.threadID)
      pending.removeAll { $0.threadID == change.current.threadID }
      batch.removeAll { $0.threadID == change.current.threadID }
      // Explicit input/selection can stop the previous spoken context. An
      // assistant response itself never selects a task or preempts the main one.
      if audio.snapshot.currentUnit?.threadID != change.current.threadID { _ = audio.interrupt() }
    case .speechRequested(let request):
      lastForegroundActivity = now()
      if audio.snapshot.currentUnit?.kind == .notification { _ = interrupt() }
      let blocks = VoiceReadableText.blocks(request.text)
      for (index, text) in blocks.enumerated() {
        let blockID = "\(request.turnID)|\(request.itemID)|\(index)"
        _ = audio.enqueue(
          VoiceAudioUnit(
            id: "live|\(request.threadID)|\(blockID)",
            groupID: request.groupID, threadID: request.threadID, turnID: request.turnID,
            itemID: request.itemID, threadTitle: request.threadTitle,
            kind: request.kind, text: text, blockID: blockID))
      }
    case .parallelResponseReady(let response):
      guard audio.settings.isEnabled, !audio.settings.isMuted else {
        orchestrator.discardPendingResponses()
        return
      }
      pending.append(response)
      pending = Array(pending.suffix(32))
      // The history keeps the full messages; no second unbounded response list.
      orchestrator.discardPendingResponses()
    case .pendingResponsesCleared(let cleared):
      pending.removeAll { $0.threadID == cleared.threadID }
      batch.removeAll { $0.threadID == cleared.threadID }
    }
  }

  private func audioEvent(_ event: VoiceAudioCoordinatorEvent) {
    switch event {
    case .unitStarted(let unit):
      activeUnit = unit
      if unit.kind != .notification { lastForegroundActivity = now() }
    case .unitFinished:
      if activeUnit?.kind == .notification {
        nextNotificationAt = now().addingTimeInterval(2)
      } else {
        lastForegroundActivity = now()
      }
      activeUnit = nil
    case .unitsDiscarded:
      activeUnit = nil
      clearNotifications()
      lastForegroundActivity = now()
    case .settingsChanged(let settings):
      if !settings.isEnabled || settings.isMuted { clearNotifications() }
      lastForegroundActivity = now()
    case .unitQueued: break
    }
    eventHandler?(event)
  }

  private func clearNotifications() {
    pending.removeAll(keepingCapacity: true)
    batch.removeAll(keepingCapacity: true)
    orchestrator.discardPendingResponses()
    nextNotificationAt = .distantPast
  }
}
