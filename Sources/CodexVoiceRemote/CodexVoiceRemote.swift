import CodexVoiceCore
import CodexVoiceMacOS
import Foundation

private struct RemoteOptions {
  var url = URL(string: "ws://127.0.0.1:\(VoiceControlProtocol.defaultPort)/control")!
  var tokenFile = VoiceControlTokenStore.defaultURL
  var clientID = "\(Host.current().localizedName ?? "macbook").codex-voice-remote"
  var sequence = UInt64(Date().timeIntervalSince1970 * 1_000_000)
  var outputJSON = false
  var command: VoiceControlCommand?

  init(arguments: [String]) throws {
    var index = 1
    while index < arguments.count {
      let argument = arguments[index]
      switch argument {
      case "--url":
        index += 1
        guard index < arguments.count, let value = URL(string: arguments[index]) else {
          throw RemoteCLIError.invalidValue("--url")
        }
        url = value
      case "--token-file":
        index += 1
        guard index < arguments.count else { throw RemoteCLIError.invalidValue("--token-file") }
        tokenFile = URL(fileURLWithPath: arguments[index]).standardizedFileURL
      case "--client-id":
        index += 1
        guard index < arguments.count else { throw RemoteCLIError.invalidValue("--client-id") }
        clientID = arguments[index]
      case "--sequence":
        index += 1
        guard index < arguments.count, let value = UInt64(arguments[index]), value > 0 else {
          throw RemoteCLIError.invalidValue("--sequence")
        }
        sequence = value
      case "--json":
        outputJSON = true
      case "--help", "-h":
        print(Self.usage)
        exit(0)
      case "state":
        try setCommand(.getState)
      case "interrupt":
        try setCommand(.interruptAudio)
      case "enable":
        try setCommand(.setVoiceEnabled(true))
      case "disable":
        try setCommand(.setVoiceEnabled(false))
      case "mute":
        try setCommand(.setMuted(true))
      case "unmute":
        try setCommand(.setMuted(false))
      case "volume":
        index += 1
        guard index < arguments.count, let value = Double(arguments[index]), (0...1).contains(value)
        else {
          throw RemoteCLIError.invalidValue("volume")
        }
        try setCommand(.setVolume(value))
      default:
        throw RemoteCLIError.unknownArgument(argument)
      }
      index += 1
    }

    guard command != nil else { throw RemoteCLIError.missingCommand }
    guard VoiceControlEndpointPolicy.isAllowed(url) else {
      throw RemoteCLIError.insecureEndpoint(url.absoluteString)
    }
  }

  static let usage = """
    Usage: codex-voice-remote [options] COMMAND

    Commands:
      state                    Affiche l'état vocal distant
      interrupt                Abandonne immédiatement toute la file audio
      enable | disable         Active ou désactive durablement la voix
      mute | unmute            Active ou retire la sourdine
      volume 0...1             Règle le volume applicatif

    Options:
      --url URL                WebSocket local (défaut: ws://127.0.0.1:48731/control)
      --token-file PATH        Jeton partagé (défaut: ~/.codex-voice/control-token)
      --client-id ID           Identifiant stable du contrôleur
      --sequence N             Séquence explicite pour le diagnostic
      --json                   Sortie JSON

    Une URL ws:// n'est acceptée que sur localhost. Pour le Mac mini distant,
    ouvrir d'abord un tunnel SSH vers son port 48731.
    """

  private mutating func setCommand(_ value: VoiceControlCommand) throws {
    guard command == nil else { throw RemoteCLIError.multipleCommands }
    command = value
  }

}

private enum RemoteCLIError: LocalizedError {
  case invalidValue(String)
  case unknownArgument(String)
  case missingCommand
  case multipleCommands
  case insecureEndpoint(String)

  var errorDescription: String? {
    switch self {
    case .invalidValue(let argument): return "Valeur absente ou invalide pour \(argument)."
    case .unknownArgument(let argument): return "Argument inconnu : \(argument)."
    case .missingCommand: return "Commande distante absente."
    case .multipleCommands: return "Une seule commande peut être envoyée à la fois."
    case .insecureEndpoint(let url):
      return "Endpoint refusé : \(url). Utiliser localhost via SSH ou une URL wss://."
    }
  }
}

private func printHumanReadable(_ message: VoiceControlMessage) {
  guard let state = message.state else {
    print("Aucun état reçu.")
    return
  }
  print(
    "Voix active : \(state.voiceEnabled), muette : \(state.muted), volume : \(state.volume), vitesse : \(state.rate)"
  )
  if let current = state.currentAudio {
    print(
      "Lecture : \(current.threadTitle ?? current.threadID) [\(current.kind)], file : \(state.queuedUnitCount)"
    )
  } else {
    print("Lecture : aucune, file : \(state.queuedUnitCount)")
  }
  print("Réponses parallèles en attente : \(state.pendingResponseCount)")
  if message.actionPerformed == true { print("Commande appliquée.") }
}

@main
private struct CodexVoiceRemoteMain {
  static func main() async {
    do {
      let options = try RemoteOptions(arguments: CommandLine.arguments)
      let token = try VoiceControlTokenStore.load(from: options.tokenFile)
      let request = VoiceControlRequest(
        clientID: options.clientID,
        sequence: options.sequence,
        authorization: token,
        command: options.command!
      )
      let response = try await VoiceControlWebSocketClient().perform(request, at: options.url)
      if options.outputJSON {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        print(String(decoding: try encoder.encode(response), as: UTF8.self))
      } else {
        printHumanReadable(response)
      }
    } catch {
      FileHandle.standardError.write(Data("Erreur : \(error.localizedDescription)\n".utf8))
      exit(1)
    }
  }
}
