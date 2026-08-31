import Foundation

enum ProbeCommand: String {
  case snapshot
  case watch
}

enum CLIError: LocalizedError {
  case invalidArgument(String)
  case missingValue(String)

  var errorDescription: String? {
    switch self {
    case .invalidArgument(let value):
      return "Argument inconnu ou invalide : \(value)"
    case .missingValue(let option):
      return "Valeur manquante après \(option)"
    }
  }
}

struct CLIOptions {
  var command: ProbeCommand = .snapshot
  var transport: ProbeTransport = .auto
  var codexPath: String = defaultCodexPath()
  var socketPath: String = defaultSocketPath()
  var limit = 20
  var historyRecent = 5
  var subscribeRecent = 2
  var watchSeconds: TimeInterval = 30
  var explicitThreadIDs: [String] = []
  var includeText = false
  var statePath: String? = ".probe/app-server-state.json"
  var outputPath: String?

  static func parse(_ arguments: [String]) throws -> CLIOptions {
    var options = CLIOptions()
    var index = 0

    if let first = arguments.first, let command = ProbeCommand(rawValue: first) {
      options.command = command
      index += 1
    }

    func requireValue(for option: String) throws -> String {
      index += 1
      guard index < arguments.count else { throw CLIError.missingValue(option) }
      return arguments[index]
    }

    while index < arguments.count {
      let argument = arguments[index]
      switch argument {
      case "--transport":
        let value = try requireValue(for: argument)
        guard let transport = ProbeTransport(rawValue: value) else {
          throw CLIError.invalidArgument("\(argument) \(value)")
        }
        options.transport = transport
      case "--codex":
        options.codexPath = try requireValue(for: argument)
      case "--socket":
        options.socketPath = try requireValue(for: argument)
      case "--limit":
        let value = try requireValue(for: argument)
        guard let number = Int(value), number > 0 else { throw CLIError.invalidArgument(value) }
        options.limit = number
      case "--history-recent":
        let value = try requireValue(for: argument)
        guard let number = Int(value), number >= 0 else { throw CLIError.invalidArgument(value) }
        options.historyRecent = number
      case "--subscribe-recent":
        let value = try requireValue(for: argument)
        guard let number = Int(value), number >= 0 else { throw CLIError.invalidArgument(value) }
        options.subscribeRecent = number
      case "--watch-seconds":
        let value = try requireValue(for: argument)
        guard let number = Double(value), number >= 0 else { throw CLIError.invalidArgument(value) }
        options.watchSeconds = number
      case "--thread":
        options.explicitThreadIDs.append(try requireValue(for: argument))
      case "--state":
        options.statePath = try requireValue(for: argument)
      case "--no-state":
        options.statePath = nil
      case "--output":
        options.outputPath = try requireValue(for: argument)
      case "--include-text":
        options.includeText = true
      case "--help", "-h":
        printUsage()
        exit(0)
      default:
        throw CLIError.invalidArgument(argument)
      }
      index += 1
    }

    return options
  }

  func resolvedTransport() -> ProbeTransport {
    guard transport == .auto else { return transport }
    return FileManager.default.fileExists(atPath: socketPath) ? .daemon : .standalone
  }

  static func printUsage() {
    print(
      """
      Usage: codex-voice-probe [snapshot|watch] [options]

        snapshot                  Liste et relit les tâches récentes sans s'abonner.
        watch                     S'abonne en lecture seule puis journalise les événements.

        --transport MODE          auto, standalone ou daemon (défaut: auto).
        --codex PATH              Chemin du binaire Codex.
        --socket PATH             Socket du daemon utilisé par le mode proxy.
        --limit N                 Nombre maximal de tâches listées (défaut: 20).
        --history-recent N        Tâches récentes relues avec leurs tours (défaut: 5).
        --subscribe-recent N      Tâches récentes suivies en mode watch (défaut: 2).
        --thread ID               Tâche à relire et suivre, option répétable.
        --watch-seconds N         Durée d'écoute (défaut: 30).
        --state PATH              Checkpoint de déduplication.
        --no-state                Désactive le checkpoint persistant.
        --output PATH             Écrit le rapport JSON détaillé.
        --include-text            Affiche de courts extraits de texte (désactivé par défaut).
      """
    )
  }
}

private func defaultCodexPath() -> String {
  if let configured = ProcessInfo.processInfo.environment["CODEX_VOICE_CODEX_BIN"],
    !configured.isEmpty
  {
    return configured
  }
  let bundled = "/Applications/ChatGPT.app/Contents/Resources/codex"
  if FileManager.default.isExecutableFile(atPath: bundled) { return bundled }
  return "/usr/local/bin/codex"
}

private func defaultSocketPath() -> String {
  let home = FileManager.default.homeDirectoryForCurrentUser.path
  return "\(home)/.codex/app-server-control/app-server-control.sock"
}
