import CodexVoiceCore
import CodexVoiceMacOS
import Foundation

@MainActor
final class VoiceRemoteViewModel: ObservableObject {
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
  @Published private(set) var currentAudio: VoiceControlCurrentAudio?
  @Published private(set) var queuedUnitCount = 0
  @Published private(set) var optionMonitoringAuthorized = false
  @Published private(set) var lastError: String?

  let configuration: VoiceRemoteConfiguration

  private let optionMonitor = GlobalOptionMonitor()
  private var connection: PersistentVoiceControlWebSocketClient?
  private var connectTask: Task<Void, Never>?
  private var reconnectTask: Task<Void, Never>?
  private var volumeTask: Task<Void, Never>?
  private var connectionGeneration = UUID()
  private var hasStarted = false

  init(configuration: VoiceRemoteConfiguration = .current()) {
    self.configuration = configuration
  }

  var deviceStatus: String {
    "\(configuration.deviceName) · \(connectionPhase.label)"
  }

  var readingTitle: String {
    guard let currentAudio else { return "Aucune conversation en lecture" }
    return currentAudio.threadTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
      .nilIfEmpty ?? "Conversation Codex"
  }

  var isReading: Bool { currentAudio != nil }
  var canStop: Bool { connectionPhase == .connected && (currentAudio != nil || queuedUnitCount > 0) }
  var controlsEnabled: Bool { connectionPhase == .connected }

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
      optionMonitoringAuthorized = true
      return
    }
    optionMonitoringAuthorized = optionMonitor.isAuthorized
    optionMonitor.start { [weak self] in self?.interruptAudio() }
    connect()
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

  func interruptAudio() {
    guard controlsEnabled else { return }
    if configuration.isPreview {
      currentAudio = nil
      queuedUnitCount = 0
      return
    }
    perform(.interruptAudio)
  }

  func requestOptionMonitoringAuthorization() {
    optionMonitoringAuthorized = optionMonitor.requestAuthorization()
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
        lastError = error.localizedDescription
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
    currentAudio = state.currentAudio
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

  var errorDescription: String? {
    switch self {
    case .insecureEndpoint(let value):
      return "Endpoint refusé : \(value). Utiliser localhost via SSH ou une URL wss://."
    }
  }
}

private extension String {
  var nilIfEmpty: String? { isEmpty ? nil : self }
}
