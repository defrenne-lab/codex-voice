import Foundation

public struct VoiceAudioSettings: Codable, Equatable, Sendable {
  public var isEnabled: Bool
  public var isMuted: Bool
  public var rate: Float
  public var voiceIdentifier: String?

  public init(
    isEnabled: Bool = false,
    isMuted: Bool = false,
    rate: Float = 0.48,
    voiceIdentifier: String? = nil
  ) {
    self.isEnabled = isEnabled
    self.isMuted = isMuted
    self.rate = Self.clampRate(rate)
    self.voiceIdentifier = voiceIdentifier
  }

  public static let safeDefaults = VoiceAudioSettings()

  static func clampRate(_ value: Float) -> Float {
    min(1, max(0.1, value))
  }
}

public protocol VoiceAudioSettingsStore: AnyObject {
  func load() -> VoiceAudioSettings?
  func save(_ settings: VoiceAudioSettings)
}

public struct VoiceAudioUnit: Equatable, Sendable {
  public let id: String
  public let groupID: String
  public let threadID: String
  public let turnID: String
  public let itemID: String
  public let threadTitle: String?
  public let kind: VoiceSpeechKind
  public let text: String

  public init(
    id: String,
    groupID: String,
    threadID: String,
    turnID: String,
    itemID: String,
    threadTitle: String?,
    kind: VoiceSpeechKind,
    text: String
  ) {
    self.id = id
    self.groupID = groupID
    self.threadID = threadID
    self.turnID = turnID
    self.itemID = itemID
    self.threadTitle = threadTitle
    self.kind = kind
    self.text = text
  }

  public init(speechRequest: VoiceSpeechRequest) {
    let groupID = "turn|\(speechRequest.threadID)|\(speechRequest.turnID)"
    self.init(
      id: "item|\(speechRequest.threadID)|\(speechRequest.turnID)|\(speechRequest.itemID)",
      groupID: groupID,
      threadID: speechRequest.threadID,
      turnID: speechRequest.turnID,
      itemID: speechRequest.itemID,
      threadTitle: speechRequest.threadTitle,
      kind: speechRequest.kind,
      text: speechRequest.text
    )
  }
}

public struct VoiceSpeechDriverRequest: Equatable, Sendable {
  public let unitID: String
  public let text: String
  public let rate: Float
  public let voiceIdentifier: String?

  public init(
    unitID: String,
    text: String,
    rate: Float,
    voiceIdentifier: String?
  ) {
    self.unitID = unitID
    self.text = text
    self.rate = rate
    self.voiceIdentifier = voiceIdentifier
  }
}

public enum VoiceSpeechDriverOutcome: Equatable, Sendable {
  case finished
  case cancelled
  case failed(String)
}

@MainActor
public protocol VoiceSpeechDriver: AnyObject {
  var completionHandler: ((String, VoiceSpeechDriverOutcome) -> Void)? { get set }
  func speak(_ request: VoiceSpeechDriverRequest)
  func stop()
}

public enum VoiceAudioEnqueueResult: Equatable, Sendable {
  case started
  case queued
  case ignoredVoiceDisabled
  case ignoredMuted
  case ignoredDismissedGroup
  case ignoredDuplicate
  case ignoredEmptyText
}

public enum VoiceAudioDiscardReason: String, Sendable {
  case interrupted
  case voiceDisabled
  case muted
  case shutdown
}

public struct VoiceAudioDiscard: Equatable, Sendable {
  public let unitIDs: [String]
  public let reason: VoiceAudioDiscardReason

  public init(unitIDs: [String], reason: VoiceAudioDiscardReason) {
    self.unitIDs = unitIDs
    self.reason = reason
  }
}

public enum VoiceAudioCoordinatorEvent: Equatable, Sendable {
  case settingsChanged(VoiceAudioSettings)
  case unitQueued(VoiceAudioUnit)
  case unitStarted(VoiceAudioUnit)
  case unitFinished(String, VoiceSpeechDriverOutcome)
  case unitsDiscarded(VoiceAudioDiscard)
}

public struct VoiceAudioSnapshot: Equatable, Sendable {
  public let settings: VoiceAudioSettings
  public let currentUnit: VoiceAudioUnit?
  public let queuedUnitCount: Int

  public init(
    settings: VoiceAudioSettings,
    currentUnit: VoiceAudioUnit?,
    queuedUnitCount: Int
  ) {
    self.settings = settings
    self.currentUnit = currentUnit
    self.queuedUnitCount = queuedUnitCount
  }
}

@MainActor
public final class VoiceAudioCoordinator {
  private let driver: VoiceSpeechDriver
  private let settingsStore: VoiceAudioSettingsStore?
  private var queue: [VoiceAudioUnit] = []
  private var currentUnit: VoiceAudioUnit?
  private var acceptedUnitIDs: Set<String> = []
  private var dismissedGroupIDs: Set<String> = []

  public private(set) var settings: VoiceAudioSettings
  public var eventHandler: ((VoiceAudioCoordinatorEvent) -> Void)?

  public init(
    driver: VoiceSpeechDriver,
    settingsStore: VoiceAudioSettingsStore? = nil,
    defaultSettings: VoiceAudioSettings = .safeDefaults
  ) {
    self.driver = driver
    self.settingsStore = settingsStore
    settings = settingsStore?.load() ?? defaultSettings
    settings.rate = VoiceAudioSettings.clampRate(settings.rate)
    driver.completionHandler = { [weak self] unitID, outcome in
      self?.driverCompleted(unitID: unitID, outcome: outcome)
    }
  }

  public var snapshot: VoiceAudioSnapshot {
    VoiceAudioSnapshot(
      settings: settings,
      currentUnit: currentUnit,
      queuedUnitCount: queue.count
    )
  }

  @discardableResult
  public func handle(_ effect: VoiceOrchestratorEffect) -> VoiceAudioEnqueueResult? {
    guard case .speechRequested(let request) = effect else { return nil }
    return enqueue(VoiceAudioUnit(speechRequest: request))
  }

  @discardableResult
  public func enqueue(_ unit: VoiceAudioUnit) -> VoiceAudioEnqueueResult {
    guard !unit.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return .ignoredEmptyText
    }
    guard settings.isEnabled else { return .ignoredVoiceDisabled }
    guard !settings.isMuted else { return .ignoredMuted }
    guard !dismissedGroupIDs.contains(unit.groupID) else { return .ignoredDismissedGroup }
    guard acceptedUnitIDs.insert(unit.id).inserted else { return .ignoredDuplicate }

    queue.append(unit)
    eventHandler?(.unitQueued(unit))
    return startNextIfPossible() ? .started : .queued
  }

  @discardableResult
  public func interrupt() -> Bool {
    let units = allEngagedUnits()
    guard !units.isEmpty else { return false }
    dismissedGroupIDs.formUnion(units.map(\.groupID))
    discardEngagedUnits(reason: .interrupted)
    return true
  }

  public func setVoiceEnabled(_ enabled: Bool) {
    guard settings.isEnabled != enabled else { return }
    settings.isEnabled = enabled
    if !enabled { discardEngagedUnits(reason: .voiceDisabled) }
    persistAndPublishSettings()
  }

  public func setMuted(_ muted: Bool) {
    guard settings.isMuted != muted else { return }
    settings.isMuted = muted
    if muted { discardEngagedUnits(reason: .muted) }
    persistAndPublishSettings()
  }

  public func setRate(_ rate: Float) {
    let clamped = VoiceAudioSettings.clampRate(rate)
    guard settings.rate != clamped else { return }
    settings.rate = clamped
    persistAndPublishSettings()
  }

  public func setVoiceIdentifier(_ identifier: String?) {
    let normalized = identifier?.trimmingCharacters(in: .whitespacesAndNewlines)
    let value = normalized?.isEmpty == false ? normalized : nil
    guard settings.voiceIdentifier != value else { return }
    settings.voiceIdentifier = value
    persistAndPublishSettings()
  }

  public func shutdown() {
    discardEngagedUnits(reason: .shutdown)
    driver.completionHandler = nil
  }

  private func startNextIfPossible() -> Bool {
    guard currentUnit == nil, settings.isEnabled, !settings.isMuted, !queue.isEmpty else {
      return false
    }
    let unit = queue.removeFirst()
    currentUnit = unit
    driver.speak(
      VoiceSpeechDriverRequest(
        unitID: unit.id,
        text: unit.text,
        rate: settings.rate,
        voiceIdentifier: settings.voiceIdentifier
      )
    )
    eventHandler?(.unitStarted(unit))
    return true
  }

  private func driverCompleted(unitID: String, outcome: VoiceSpeechDriverOutcome) {
    guard currentUnit?.id == unitID else { return }
    currentUnit = nil
    eventHandler?(.unitFinished(unitID, outcome))
    _ = startNextIfPossible()
  }

  private func allEngagedUnits() -> [VoiceAudioUnit] {
    (currentUnit.map { [$0] } ?? []) + queue
  }

  private func discardEngagedUnits(reason: VoiceAudioDiscardReason) {
    let units = allEngagedUnits()
    let hadCurrent = currentUnit != nil
    currentUnit = nil
    queue.removeAll(keepingCapacity: true)
    if hadCurrent { driver.stop() }
    if !units.isEmpty {
      eventHandler?(
        .unitsDiscarded(VoiceAudioDiscard(unitIDs: units.map(\.id), reason: reason))
      )
    }
  }

  private func persistAndPublishSettings() {
    settingsStore?.save(settings)
    eventHandler?(.settingsChanged(settings))
  }
}
