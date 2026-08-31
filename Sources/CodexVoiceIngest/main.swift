import CodexVoiceCore
import Foundation

struct IngestOptions {
  var sessionsRoot = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".codex/sessions", isDirectory: true)
  var startPosition = CodexTranscriptStartPosition.end
  var watchSeconds: TimeInterval = 5
  var pollMilliseconds: UInt32 = 250
  var maximumFiles = 64
  var reconcileAppServer = false
  var snapshotLimit = 5
  var codexPath = Self.defaultCodexPath()
  var threadIDs: Set<String> = []

  init(arguments: [String]) throws {
    var index = 1
    while index < arguments.count {
      switch arguments[index] {
      case "--sessions-root":
        index += 1
        guard index < arguments.count else { throw CLIError.missingValue("--sessions-root") }
        sessionsRoot = URL(fileURLWithPath: arguments[index]).standardizedFileURL
      case "--from-beginning":
        startPosition = .beginning
      case "--watch-seconds":
        index += 1
        guard index < arguments.count, let value = TimeInterval(arguments[index]) else {
          throw CLIError.missingValue("--watch-seconds")
        }
        watchSeconds = max(0, value)
      case "--poll-ms":
        index += 1
        guard index < arguments.count, let value = UInt32(arguments[index]) else {
          throw CLIError.missingValue("--poll-ms")
        }
        pollMilliseconds = max(20, value)
      case "--max-files":
        index += 1
        guard index < arguments.count, let value = Int(arguments[index]) else {
          throw CLIError.missingValue("--max-files")
        }
        maximumFiles = max(1, value)
      case "--reconcile-app-server":
        reconcileAppServer = true
      case "--snapshot-limit":
        index += 1
        guard index < arguments.count, let value = Int(arguments[index]) else {
          throw CLIError.missingValue("--snapshot-limit")
        }
        snapshotLimit = max(1, value)
      case "--codex":
        index += 1
        guard index < arguments.count else { throw CLIError.missingValue("--codex") }
        codexPath = arguments[index]
      case "--thread":
        index += 1
        guard index < arguments.count else { throw CLIError.missingValue("--thread") }
        threadIDs.insert(arguments[index])
      case "--help", "-h":
        print(Self.usage)
        exit(0)
      default:
        throw CLIError.unknownArgument(arguments[index])
      }
      index += 1
    }
  }

  static let usage = """
    Usage: codex-voice-ingest [options]
      --sessions-root PATH   Racine des transcriptions (défaut: ~/.codex/sessions)
      --from-beginning       Rejoue les fichiers suivis au lieu de démarrer à la fin
      --watch-seconds N      Durée d'observation (défaut: 5)
      --poll-ms N            Intervalle de lecture (défaut: 250)
      --max-files N          Nombre maximal de fichiers récents (défaut: 64)
      --reconcile-app-server Confirme l'état avec des instantanés App Server
      --snapshot-limit N     Nombre de tâches récentes à confirmer (défaut: 5)
      --codex PATH           Chemin du binaire Codex
      --thread ID            Limite le JSONL à cette tâche (option répétable)
    """

  private static func defaultCodexPath() -> String {
    if let configured = ProcessInfo.processInfo.environment["CODEX_VOICE_CODEX_BIN"],
      !configured.isEmpty
    {
      return configured
    }
    let bundled = "/Applications/ChatGPT.app/Contents/Resources/codex"
    if FileManager.default.isExecutableFile(atPath: bundled) { return bundled }
    return "/usr/local/bin/codex"
  }
}

enum CLIError: LocalizedError {
  case missingValue(String)
  case unknownArgument(String)

  var errorDescription: String? {
    switch self {
    case .missingValue(let option): return "Valeur absente ou invalide pour \(option)."
    case .unknownArgument(let value): return "Argument inconnu : \(value)."
    }
  }
}

func eventKind(_ payload: CodexEventPayload) -> String {
  switch payload {
  case .threadObserved: return "thread"
  case .turnStarted: return "turn-started"
  case .userMessageCompleted: return "user-message"
  case .assistantMessageCompleted(let message):
    return "assistant-\(message.phase.rawValue ?? "unknown")"
  case .turnCompleted: return "turn-completed"
  }
}

func routingKind(_ effect: VoiceOrchestratorEffect) -> String {
  switch effect {
  case .mainConversationChanged: return "main-conversation-changed"
  case .speechRequested(let request): return "speech-\(request.kind.rawValue)"
  case .parallelResponseReady: return "parallel-response-ready"
  case .pendingResponsesCleared: return "pending-responses-cleared"
  }
}

do {
  let options = try IngestOptions(arguments: CommandLine.arguments)
  let source = JSONLTranscriptEventSource(
    sessionsRoot: options.sessionsRoot,
    startPosition: options.startPosition,
    maximumTrackedFiles: options.maximumFiles,
    includedThreadIDs: options.threadIDs
  )
  let composite = CompositeCodexEventSource()
  let orchestrator = VoiceOrchestrator()
  try source.prime()

  var dispositions: [CompositeDisposition: Int] = [:]
  var kinds: [String: Int] = [:]
  var diagnostics = 0
  var jsonlEvents = 0
  var snapshotEvents = 0
  var observedThreadIDs: [String] = []
  var observedThreadIDSet: Set<String> = []
  var routingEffects: [String: Int] = [:]
  let deadline = Date().addingTimeInterval(options.watchSeconds)
  repeat {
    let batch = try source.poll()
    jsonlEvents += batch.events.count
    diagnostics += batch.diagnostics.count
    for event in batch.events where observedThreadIDSet.insert(event.payload.threadID).inserted {
      observedThreadIDs.append(event.payload.threadID)
    }
    for result in composite.ingest(batch.events) {
      dispositions[result.disposition, default: 0] += 1
      if result.isNewTimelineEvent {
        kinds[eventKind(result.event.payload), default: 0] += 1
      }
      for effect in orchestrator.process(result) {
        routingEffects[routingKind(effect), default: 0] += 1
      }
    }
    if Date() < deadline { usleep(options.pollMilliseconds * 1_000) }
  } while Date() < deadline

  if options.reconcileAppServer {
    let reader = AppServerSnapshotReader(
      executableURL: URL(fileURLWithPath: options.codexPath)
    )
    let snapshots =
      try observedThreadIDs.isEmpty
      ? reader.readRecentThreads(limit: options.snapshotLimit)
      : reader.readThreads(Array(observedThreadIDs.prefix(options.snapshotLimit)))
    snapshotEvents = snapshots.events.count
    diagnostics += snapshots.diagnostics.count
    for result in composite.ingest(snapshots.events) {
      dispositions[result.disposition, default: 0] += 1
      if result.isNewTimelineEvent {
        kinds[eventKind(result.event.payload), default: 0] += 1
      }
      for effect in orchestrator.process(result) {
        routingEffects[routingKind(effect), default: 0] += 1
      }
    }
  }

  print("Codex Voice · ingestion composite")
  print("Racine : \(options.sessionsRoot.path)")
  print("Événements uniques : \(composite.knownEventCount)")
  print("Types : \(kinds.sorted { $0.key < $1.key })")
  print("Décisions : \(dispositions.sorted { $0.key.rawValue < $1.key.rawValue })")
  print("Routage simulé : \(routingEffects.sorted { $0.key < $1.key })")
  print("Réponses parallèles en attente : \(orchestrator.snapshot.pendingResponses.count)")
  print("Diagnostics : \(diagnostics)")
  print("Événements JSONL normalisés : \(jsonlEvents)")
  if options.reconcileAppServer {
    print("Événements App Server normalisés : \(snapshotEvents)")
  }
  print("Contenu des messages : non affiché")
} catch {
  FileHandle.standardError.write(Data("Erreur : \(error.localizedDescription)\n".utf8))
  exit(1)
}
