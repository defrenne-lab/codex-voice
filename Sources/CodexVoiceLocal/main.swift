import CodexVoiceCore
import CodexVoiceMacOS
import Foundation

struct LocalOptions {
  var sessionsRoot = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".codex/sessions", isDirectory: true)
  var pollMilliseconds: UInt32 = 200
  var watchSeconds: TimeInterval = 60
  var runForever = false
  var maximumFiles = 16
  var threadIDs: Set<String> = []
  var voiceEnabled: Bool?
  var muted: Bool?
  var volume: Float?
  var rate: Float?
  var voiceIdentifier: String?
  var shouldSetVoiceIdentifier = false
  var listVoices = false
  var controlServerEnabled = true
  var controlPort = VoiceControlProtocol.defaultPort
  var controlTokenFile = VoiceControlTokenStore.defaultURL

  init(arguments: [String]) throws {
    var index = 1
    while index < arguments.count {
      switch arguments[index] {
      case "--sessions-root":
        index += 1
        guard index < arguments.count else { throw LocalCLIError.missingValue("--sessions-root") }
        sessionsRoot = URL(fileURLWithPath: arguments[index]).standardizedFileURL
      case "--poll-ms":
        index += 1
        guard index < arguments.count, let value = UInt32(arguments[index]) else {
          throw LocalCLIError.missingValue("--poll-ms")
        }
        pollMilliseconds = max(20, value)
      case "--watch-seconds":
        index += 1
        guard index < arguments.count, let value = TimeInterval(arguments[index]), value >= 0 else {
          throw LocalCLIError.missingValue("--watch-seconds")
        }
        watchSeconds = value
      case "--forever":
        runForever = true
      case "--max-files":
        index += 1
        guard index < arguments.count, let value = Int(arguments[index]), value > 0 else {
          throw LocalCLIError.missingValue("--max-files")
        }
        maximumFiles = value
      case "--thread":
        index += 1
        guard index < arguments.count else { throw LocalCLIError.missingValue("--thread") }
        threadIDs.insert(arguments[index])
      case "--enable-voice":
        voiceEnabled = true
      case "--disable-voice":
        voiceEnabled = false
      case "--mute":
        muted = true
      case "--unmute":
        muted = false
      case "--volume":
        index += 1
        guard index < arguments.count, let value = Float(arguments[index]) else {
          throw LocalCLIError.missingValue("--volume")
        }
        volume = value
      case "--rate":
        index += 1
        guard index < arguments.count, let value = Float(arguments[index]) else {
          throw LocalCLIError.missingValue("--rate")
        }
        rate = value
      case "--voice":
        index += 1
        guard index < arguments.count else { throw LocalCLIError.missingValue("--voice") }
        voiceIdentifier = arguments[index]
        shouldSetVoiceIdentifier = true
      case "--system-voice":
        voiceIdentifier = nil
        shouldSetVoiceIdentifier = true
      case "--list-voices":
        listVoices = true
      case "--control-port":
        index += 1
        guard index < arguments.count, let value = UInt16(arguments[index]), value > 0 else {
          throw LocalCLIError.missingValue("--control-port")
        }
        controlPort = value
      case "--control-token-file":
        index += 1
        guard index < arguments.count else {
          throw LocalCLIError.missingValue("--control-token-file")
        }
        controlTokenFile = URL(fileURLWithPath: arguments[index]).standardizedFileURL
      case "--no-control-server":
        controlServerEnabled = false
      case "--help", "-h":
        print(Self.usage)
        exit(0)
      default:
        throw LocalCLIError.unknownArgument(arguments[index])
      }
      index += 1
    }
  }

  static let usage = """
    Usage: codex-voice-local [options]

      --enable-voice         Active et mémorise la lecture automatique
      --disable-voice        Désactive immédiatement et mémorise cet état
      --mute | --unmute      Change la sourdine persistante
      --volume 0...1         Règle le volume système du Mac
      --rate 0.1...1         Règle la vitesse (0.48 par défaut)
      --voice IDENTIFIER     Sélectionne une voix macOS
      --system-voice         Revient à la voix française du système
      --list-voices          Liste les voix françaises sans produire de son
      --watch-seconds N      Observe les nouveaux événements pendant N secondes (défaut: 60)
      --forever              Observe jusqu'à l'arrêt du processus
      --thread ID            Limite l'observation à cette tâche (option répétable)
      --sessions-root PATH   Racine des transcriptions
      --poll-ms N            Intervalle de lecture (défaut: 200)
      --max-files N          Nombre maximal de fichiers actifs (défaut: 16)
      --control-port N       Port WebSocket local (défaut: 48731)
      --control-token-file P Fichier du jeton partagé
      --no-control-server    Désactive le serveur de télécommande

    Le programme démarre toujours à la fin des journaux : aucun historique n'est lu à voix haute.
    Une nouvelle installation conserve la voix désactivée jusqu'à --enable-voice.
    """
}

enum LocalCLIError: LocalizedError {
  case missingValue(String)
  case unknownArgument(String)
  case systemVolumeUnavailable

  var errorDescription: String? {
    switch self {
    case .missingValue(let option): return "Valeur absente ou invalide pour \(option)."
    case .unknownArgument(let value): return "Argument inconnu : \(value)."
    case .systemVolumeUnavailable:
      return "Le volume système du périphérique de sortie ne peut pas être modifié."
    }
  }
}

func describe(_ event: VoiceAudioCoordinatorEvent) -> String {
  switch event {
  case .settingsChanged(let settings):
    return
      "réglages actif=\(settings.isEnabled) muet=\(settings.isMuted) vitesse=\(settings.rate)"
  case .unitQueued(let unit):
    return "mise en file \(unit.kind.rawValue) caractères=\(unit.text.count)"
  case .unitStarted(let unit):
    return "lecture \(unit.kind.rawValue) caractères=\(unit.text.count)"
  case .unitFinished(_, let outcome):
    return "fin \(String(describing: outcome))"
  case .unitsDiscarded(let discard):
    return "abandon \(discard.unitIDs.count) unité(s) raison=\(discard.reason.rawValue)"
  }
}

@MainActor
func runLocal() async throws {
  let options = try LocalOptions(arguments: CommandLine.arguments)
  if options.listVoices {
    for voice in MacOSSpeechDriver.availableFrenchVoices() {
      print("\(voice.name) [\(voice.language)]\n  \(voice.identifier)")
    }
    exit(0)
  }

  let pronunciationDictionary = PronunciationDictionary.current()
  let driver = MacOSSpeechDriver(pronunciationDictionary: pronunciationDictionary)
  let systemVolume = MacOSSystemVolumeController()
  let store = UserDefaultsVoiceAudioSettingsStore()
  let audio = VoiceAudioCoordinator(driver: driver, settingsStore: store)
  if let value = options.voiceEnabled { audio.setVoiceEnabled(value) }
  if let value = options.muted { audio.setMuted(value) }
  if let value = options.volume, !systemVolume.setVolume(value) {
    throw LocalCLIError.systemVolumeUnavailable
  }
  if let value = options.rate { audio.setRate(value) }
  if options.shouldSetVoiceIdentifier { audio.setVoiceIdentifier(options.voiceIdentifier) }

  let source = JSONLTranscriptEventSource(
    sessionsRoot: options.sessionsRoot,
    startPosition: .end,
    maximumTrackedFiles: options.maximumFiles,
    includedThreadIDs: options.threadIDs,
    includeRecentHistory: true
  )
  let titleSource = SessionIndexThreadEventSource(
    fileURL: options.sessionsRoot.deletingLastPathComponent()
      .appendingPathComponent("session_index.jsonl", isDirectory: false)
  )
  let composite = CompositeCodexEventSource()
  let orchestrator = VoiceOrchestrator()
  let readingSession = VoiceReadingSession(audio: audio, orchestrator: orchestrator)
  let controlServer: VoiceControlWebSocketServer?
  if options.controlServerEnabled {
    let token = try VoiceControlTokenStore.loadOrCreate(at: options.controlTokenFile)
    let installedVoices = MacOSSpeechDriver.availableFrenchVoices().map {
      VoiceControlVoice(identifier: $0.identifier, name: $0.name, language: $0.language)
    }
    let service = VoiceControlService(
      authorizationToken: token,
      audio: audio,
      systemVolume: systemVolume,
      pronunciationDictionary: pronunciationDictionary,
      pendingResponseCount: { orchestrator.snapshot.pendingResponses.count },
      mainConversation: {
        let snapshot = orchestrator.snapshot
        guard let main = snapshot.mainConversation else { return nil }
        return VoiceControlConversation(
          threadID: main.threadID,
          turnID: main.turnID,
          threadTitle: snapshot.threads.first { $0.threadID == main.threadID }?.title
        )
      },
      availableVoices: { installedVoices },
      readingSession: readingSession
    )
    let server = VoiceControlWebSocketServer(service: service)
    server.eventHandler = { event in
      switch event {
      case .ready(let port): print("[contrôle] prêt sur 127.0.0.1:\(port)")
      case .clientConnected: print("[contrôle] client connecté")
      case .clientDisconnected: print("[contrôle] client déconnecté")
      case .commandReceived(let kind): print("[contrôle] commande \(kind.rawValue)")
      case .responseSent(let status): print("[contrôle] réponse \(status.rawValue)")
      case .failed(let message): print("[contrôle] erreur : \(message)")
      }
    }
    try server.start(port: options.controlPort)
    controlServer = server
  } else {
    controlServer = nil
  }
  if let controlServer {
    readingSession.eventHandler = { [weak controlServer] event in
      print("[audio] \(describe(event))")
      controlServer?.publishState()
    }
  } else {
    readingSession.eventHandler = { print("[audio] \(describe($0))") }
  }
  try source.prime()
  for ingestion in composite.ingest(source.takeRecentHistory()) {
    readingSession.process(ingestion)
  }

  print("Codex Voice local")
  print(
    "Voix active : \(audio.settings.isEnabled), muette : \(audio.settings.isMuted), volume système : \(systemVolume.volume), vitesse : \(audio.settings.rate)"
  )
  print("Dictionnaire : \(pronunciationDictionary.fileURL.path)")
  print("Démarrage à la fin des journaux : aucun rattrapage audio")
  if options.controlServerEnabled {
    print("Contrôle local authentifié : 127.0.0.1:\(options.controlPort)")
    print("Jeton : \(options.controlTokenFile.path) (contenu masqué)")
  }

  var observedEvents = 0
  var diagnostics = 0
  var nextTitlePoll = Date.distantPast
  let deadline = Date().addingTimeInterval(options.watchSeconds)
  repeat {
    let now = Date()
    let titleBatch: CodexEventBatch
    if now >= nextTitlePoll {
      titleBatch = titleSource.poll()
      nextTitlePoll = now.addingTimeInterval(1)
    } else {
      titleBatch = CodexEventBatch()
    }
    let batch = try source.poll()
    let events = titleBatch.events + source.takeRecentHistory() + batch.events
    observedEvents += events.count
    diagnostics += titleBatch.diagnostics.count + batch.diagnostics.count
    for ingestion in composite.ingest(events) {
      readingSession.process(ingestion)
    }
    readingSession.tick()
    if !events.isEmpty { controlServer?.publishState() }

    if options.runForever || Date() < deadline {
      try await Task.sleep(
        nanoseconds: UInt64(options.pollMilliseconds) * 1_000_000
      )
    }
  } while options.runForever || Date() < deadline

  controlServer?.stop()
  audio.shutdown()
  print(
    "Arrêt : \(observedEvents) événements, \(diagnostics) diagnostics"
  )
}

Task { @MainActor in
  do {
    try await runLocal()
    exit(0)
  } catch {
    FileHandle.standardError.write(Data("Erreur : \(error.localizedDescription)\n".utf8))
    exit(1)
  }
}
dispatchMain()
