import AppKit
import CodexVoiceCore
import CodexVoiceMacOS
import Foundation

@MainActor
final class VoiceRemoteViewModel: ObservableObject {
  struct RatePreset: Identifiable {
    let label: String
    let value: Double

    var id: Double { value }
  }

  enum ConnectionPhase: Equatable {
    case connecting
    case connected
    case disconnected

    var label: String {
      switch self {
      case .connecting: return "Connexion…"
      case .connected: return "Connecté"
      case .disconnected: return "Hors ligne"
      }
    }
  }

  enum HaloState {
    case active
    case inactive
    case disconnected
  }

  @Published private(set) var connectionPhase: ConnectionPhase = .connecting
  @Published private(set) var voiceEnabled = false
  @Published private(set) var muted = false
  @Published private(set) var volume = 0.8
  @Published private(set) var rate = 0.48
  @Published private(set) var voiceIdentifier: String?
  @Published private(set) var availableVoices: [VoiceControlVoice] = []
  @Published private(set) var currentAudio: VoiceControlCurrentAudio?
  @Published private(set) var mainConversation: VoiceControlConversation?
  @Published private(set) var conversations: [VoiceControlConversation] = []
  @Published private(set) var historyState: VoiceHistoryNavigationState?
  @Published private(set) var pendingNotificationCount = 0
  @Published private(set) var queuedUnitCount = 0
  @Published private(set) var optionMonitoringAuthorized = false
  @Published private(set) var pronunciationDictionaryStatus = "TextEdit"
  @Published private(set) var lastError: String?

  let configuration: VoiceRemoteConfiguration
  var optionPressedHandler: (() -> Void)?

  private let optionMonitor = GlobalOptionMonitor()
  private let tunnelManager = SSHTunnelManager()
  private var connection: PersistentVoiceControlWebSocketClient?
  private var connectTask: Task<Void, Never>?
  private var reconnectTask: Task<Void, Never>?
  private var volumeTask: Task<Void, Never>?
  private var dictionarySyncTask: Task<Void, Never>?
  private var dictionaryLastObservedContent: String?
  private var dictionaryPendingContent: String?
  private var connectionGeneration = UUID()
  private var hasStarted = false

  let ratePresets = [
    RatePreset(label: "Lente", value: 0.38),
    RatePreset(label: "Normale", value: 0.48),
    RatePreset(label: "Rapide", value: 0.53),
    RatePreset(label: "Très rapide", value: 0.58),
  ]

  init(configuration: VoiceRemoteConfiguration = .current()) {
    self.configuration = configuration
    tunnelManager.stateHandler = { [weak self] state in
      self?.handleTunnelState(state)
    }
  }

  var deviceStatus: String {
    "\(configuration.deviceName) · \(connectionPhase.label)"
  }

  var readingTitle: String {
    if let currentAudio {
      return currentAudio.threadTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        .nilIfEmpty ?? "Conversation Codex"
    }
    guard let mainConversation else { return "Aucune conversation principale" }
    return mainConversation.threadTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
      .nilIfEmpty ?? "Conversation Codex"
  }

  var isReading: Bool { currentAudio != nil }
  var canStop: Bool {
    connectionPhase == .connected
      && (currentAudio != nil || queuedUnitCount > 0 || pendingNotificationCount > 0)
  }
  var mainConversationTitle: String {
    mainConversation?.threadTitle?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
      ?? (mainConversation == nil ? "Choisir une conversation" : "Conversation Codex")
  }
  var canGoPrevious: Bool {
    controlsEnabled && voiceEnabled && !muted && historyState?.canGoPrevious == true
  }
  var canGoNext: Bool {
    controlsEnabled && voiceEnabled && !muted && historyState?.canGoNext == true
  }
  var readingStatus: String {
    switch currentAudio?.kind {
    case "notification": return "Notification · \(readingTitle)"
    case "history": return "Réécoute d’un bloc"
    case .some: return "Lecture en cours"
    case nil: return "En attente"
    }
  }
  var controlsEnabled: Bool { connectionPhase == .connected }
  var canOpenScreenSharing: Bool { configuration.screenSharingURL != nil }

  var preferredVoices: [VoiceControlVoice] {
    ["thomas", "aurelie"].compactMap { expectedName in
      VoiceControlVoiceCatalog.recommendedFrenchVoice(
        named: expectedName,
        from: availableVoices
      )
    }
  }

  var selectedVoiceName: String {
    guard let voiceIdentifier else { return "Automatique" }
    return availableVoices.first { $0.identifier == voiceIdentifier }?.name ?? "Voix choisie"
  }

  var selectedRateName: String {
    ratePresets.first { abs($0.value - rate) < 0.01 }?.label
      ?? "\(Int((rate * 100).rounded())) %"
  }

  var haloState: HaloState {
    guard connectionPhase == .connected else { return .disconnected }
    return voiceEnabled && !muted ? .active : .inactive
  }

  func start() {
    guard !hasStarted else { return }
    hasStarted = true
    if configuration.isPreview {
      connectionPhase = .connected
      voiceEnabled = true
      muted = false
      volume = 0.8
      rate = 0.53
      availableVoices = [
        VoiceControlVoice(
          identifier: "com.apple.voice.enhanced.fr-FR.Thomas",
          name: "Thomas (Enhanced)",
          language: "fr-FR"
        ),
        VoiceControlVoice(
          identifier: "com.apple.voice.enhanced.fr-FR.Aurelie",
          name: "Aurélie (Enhanced)",
          language: "fr-FR"
        ),
      ]
      currentAudio = VoiceControlCurrentAudio(
        unit: VoiceAudioUnit(
          id: "preview-item",
          groupID: "preview-turn",
          threadID: "preview-thread",
          turnID: "preview-turn",
          itemID: "preview-item",
          threadTitle: "Améliorer la fusion",
          kind: .finalAnswer,
          text: "Aperçu sans lecture audio."
        )
      )
      mainConversation = VoiceControlConversation(
        threadID: "preview-thread",
        turnID: "preview-turn",
        threadTitle: "Améliorer la fusion"
      )
      conversations = [
        mainConversation!,
        VoiceControlConversation(
          threadID: "preview-secondary",
          turnID: "preview-turn-2", threadTitle: "Optimisation GitHub"),
      ]
      historyState = VoiceHistoryNavigationState(
        canGoPrevious: true, canGoNext: true,
        blockCount: 12, selectedBlock: 8)
      optionMonitoringAuthorized = true
      return
    }
    optionMonitoringAuthorized = optionMonitor.isAuthorized
    optionMonitor.start { [weak self] in
      self?.interruptAudio()
      self?.optionPressedHandler?()
    }
    startManagedTunnelIfConfigured()
    connect()
  }

  func shutdown() {
    optionMonitor.stop()
    connectTask?.cancel()
    reconnectTask?.cancel()
    volumeTask?.cancel()
    dictionarySyncTask?.cancel()
    tunnelManager.stop()
    let currentConnection = connection
    connection = nil
    Task { await currentConnection?.disconnect() }
  }

  func setVoiceEnabled(_ enabled: Bool) {
    guard controlsEnabled else { return }
    voiceEnabled = enabled
    if configuration.isPreview { return }
    perform(.setVoiceEnabled(enabled))
  }

  func setVolume(_ newValue: Double) {
    guard controlsEnabled else { return }
    volume = min(1, max(0, newValue))
    if configuration.isPreview { return }
    volumeTask?.cancel()
    let requestedVolume = volume
    volumeTask = Task { [weak self] in
      try? await Task.sleep(nanoseconds: 120_000_000)
      guard !Task.isCancelled else { return }
      self?.perform(.setVolume(requestedVolume))
    }
  }

  func setRate(_ newValue: Double) {
    guard controlsEnabled else { return }
    rate = min(1, max(0.1, newValue))
    if configuration.isPreview { return }
    perform(.setRate(rate))
  }

  func setVoiceIdentifier(_ identifier: String?) {
    guard controlsEnabled else { return }
    voiceIdentifier = identifier
    if configuration.isPreview { return }
    perform(.setVoiceIdentifier(identifier))
  }

  func interruptAudio() {
    guard controlsEnabled else { return }
    if configuration.isPreview {
      currentAudio = nil
      queuedUnitCount = 0
      pendingNotificationCount = 0
      return
    }
    perform(.interruptAudio)
  }

  func selectConversation(_ conversation: VoiceControlConversation) {
    guard controlsEnabled else { return }
    if configuration.isPreview {
      mainConversation = conversation
      currentAudio = nil
      return
    }
    perform(.selectConversation(conversation.threadID))
  }

  func navigateHistory(forward: Bool) {
    guard forward ? canGoNext : canGoPrevious else { return }
    if configuration.isPreview { return }
    perform(forward ? .nextBlock : .previousBlock)
  }

  func requestOptionMonitoringAuthorization() {
    optionMonitoringAuthorized = optionMonitor.requestAuthorization()
  }

  func openPronunciationDictionary() {
    guard controlsEnabled else { return }
    if configuration.isPreview {
      pronunciationDictionaryStatus = "Synchronisé"
      return
    }
    guard let connection else { return }
    pronunciationDictionaryStatus = "Ouverture…"

    Task { [weak self] in
      do {
        let response = try await connection.send(.getPronunciationDictionary)
        guard let self,
          let content = response.pronunciationDictionary?.content
        else {
          throw VoiceRemoteViewModelError.missingPronunciationDictionary
        }
        if let state = response.state { apply(state) }
        let fileURL = try prepareLocalPronunciationDictionary(content)
        dictionaryLastObservedContent = content
        dictionaryPendingContent = nil
        startPronunciationDictionarySync(fileURL: fileURL)
        openInTextEdit(fileURL)
        pronunciationDictionaryStatus = "Synchronisé"
        lastError = nil
      } catch {
        guard let self else { return }
        pronunciationDictionaryStatus = "Indisponible"
        lastError = error.localizedDescription
      }
    }
  }

  func openScreenSharing() {
    guard let url = configuration.screenSharingURL else {
      lastError = "L’adresse du Mac mini manque dans la configuration SSH."
      return
    }
    guard NSWorkspace.shared.open(url) else {
      lastError = "Le partage d’écran n’a pas pu être ouvert."
      return
    }
    lastError = nil
  }

  func reconnect() {
    reconnectTask?.cancel()
    let previousConnection = connection
    connection = nil
    Task { await previousConnection?.disconnect() }
    connect()
  }

  private func connect() {
    connectTask?.cancel()
    reconnectTask?.cancel()
    let generation = UUID()
    connectionGeneration = generation
    connectionPhase = .connecting
    lastError = nil

    connectTask = Task { [weak self] in
      guard let self else { return }
      do {
        guard VoiceControlEndpointPolicy.isAllowed(configuration.url) else {
          throw VoiceRemoteViewModelError.insecureEndpoint(configuration.url.absoluteString)
        }
        let token = try VoiceControlTokenStore.load(from: configuration.tokenFile)
        let client = PersistentVoiceControlWebSocketClient(
          url: configuration.url,
          authorizationToken: token,
          clientID: configuration.clientID
        )
        connection = client
        let initialState = try await client.connect { [weak self] event in
          Task { @MainActor [weak self] in self?.handle(event, generation: generation) }
        }
        guard !Task.isCancelled, connectionGeneration == generation else {
          await client.disconnect()
          return
        }
        apply(initialState)
        connectionPhase = .connected
        lastError = nil
      } catch {
        guard !Task.isCancelled, connectionGeneration == generation else { return }
        connection = nil
        connectionPhase = .disconnected
        if case .failed(let message) = tunnelManager.state {
          lastError = "Tunnel SSH : \(message)"
        } else {
          lastError = error.localizedDescription
        }
        scheduleReconnect()
      }
    }
  }

  private func handle(
    _ event: PersistentVoiceControlClientEvent,
    generation: UUID
  ) {
    guard connectionGeneration == generation else { return }
    switch event {
    case .stateChanged(let state):
      apply(state)
      if connectionPhase != .connected { connectionPhase = .connected }
      lastError = nil
    case .disconnected(let message):
      connection = nil
      connectionPhase = .disconnected
      lastError = message
      scheduleReconnect()
    }
  }

  private func apply(_ state: VoiceControlState) {
    voiceEnabled = state.voiceEnabled
    muted = state.muted
    volume = Double(state.volume)
    rate = Double(state.rate)
    voiceIdentifier = state.voiceIdentifier
    if let voices = state.availableVoices { availableVoices = voices }
    currentAudio = state.currentAudio
    mainConversation = state.mainConversation
    conversations = state.conversations ?? []
    historyState = state.history
    pendingNotificationCount = state.pendingResponseCount
    queuedUnitCount = state.queuedUnitCount
  }

  private func perform(_ command: VoiceControlCommand) {
    guard let connection else { return }
    Task { [weak self] in
      do {
        let response = try await connection.send(command)
        guard let self else { return }
        if let state = response.state { apply(state) }
        lastError = nil
      } catch {
        guard let self else { return }
        lastError = error.localizedDescription
      }
    }
  }

  private func prepareLocalPronunciationDictionary(_ content: String) throws -> URL {
    let directory = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(
        "Library/Application Support/Codex Voice 3 Remote",
        isDirectory: true
      )
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    let fileURL = directory.appendingPathComponent(PronunciationDictionary.fileName)
    try content.write(to: fileURL, atomically: true, encoding: .utf8)
    return fileURL
  }

  private func openInTextEdit(_ fileURL: URL) {
    guard
      let textEditURL = NSWorkspace.shared.urlForApplication(
        withBundleIdentifier: "com.apple.TextEdit"
      )
    else {
      NSWorkspace.shared.open(fileURL)
      return
    }
    let configuration = NSWorkspace.OpenConfiguration()
    NSWorkspace.shared.open(
      [fileURL],
      withApplicationAt: textEditURL,
      configuration: configuration
    )
  }

  private func startPronunciationDictionarySync(fileURL: URL) {
    dictionarySyncTask?.cancel()
    dictionarySyncTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: 750_000_000)
        guard !Task.isCancelled, let self else { return }

        if let content = try? String(contentsOf: fileURL, encoding: .utf8),
          content != dictionaryLastObservedContent
        {
          dictionaryLastObservedContent = content
          do {
            try PronunciationDictionary.validate(content)
            dictionaryPendingContent = content
            pronunciationDictionaryStatus = "À synchroniser"
          } catch {
            dictionaryPendingContent = nil
            pronunciationDictionaryStatus = "Format invalide"
          }
        }

        guard let content = dictionaryPendingContent,
          connectionPhase == .connected,
          let connection
        else { continue }

        do {
          pronunciationDictionaryStatus = "Synchronisation…"
          let response = try await connection.send(.setPronunciationDictionary(content))
          if let state = response.state { apply(state) }
          dictionaryPendingContent = nil
          pronunciationDictionaryStatus = "Synchronisé"
          lastError = nil
        } catch {
          pronunciationDictionaryStatus = "À synchroniser"
          lastError = error.localizedDescription
          try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
      }
    }
  }

  private func startManagedTunnelIfConfigured() {
    guard configuration.supportsManagedSSHTunnel,
      let target = configuration.initialSSHTarget?.nilIfEmpty
    else { return }
    do {
      let specification = try SSHTunnelSpecification(
        target: target,
        localPort: configuration.url.port ?? Int(VoiceControlProtocol.defaultPort)
      )
      tunnelManager.start(specification)
    } catch {
      lastError = error.localizedDescription
    }
  }

  private func handleTunnelState(_ state: SSHTunnelManager.State) {
    switch state {
    case .running:
      if connectionPhase == .disconnected { reconnect() }
    case .failed(let message):
      if connectionPhase != .connected { lastError = "Tunnel SSH : \(message)" }
    case .idle, .starting:
      break
    }
  }

  private func scheduleReconnect() {
    guard reconnectTask == nil || reconnectTask?.isCancelled == true else { return }
    reconnectTask = Task { [weak self] in
      try? await Task.sleep(nanoseconds: 2_000_000_000)
      guard !Task.isCancelled else { return }
      self?.reconnectTask = nil
      self?.connect()
    }
  }
}

private enum VoiceRemoteViewModelError: LocalizedError {
  case insecureEndpoint(String)
  case missingPronunciationDictionary

  var errorDescription: String? {
    switch self {
    case .insecureEndpoint(let value):
      return "Endpoint refusé : \(value). Utiliser localhost via SSH ou une URL wss://."
    case .missingPronunciationDictionary:
      return "Le service vocal n’a pas renvoyé le dictionnaire de prononciation."
    }
  }
}

extension String {
  fileprivate var nilIfEmpty: String? { isEmpty ? nil : self }
}
