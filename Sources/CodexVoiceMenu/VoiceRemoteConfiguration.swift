import CodexVoiceCore
import CodexVoiceMacOS
import Foundation

struct VoiceRemoteConfiguration {
  let url: URL
  let tokenFile: URL
  let deviceName: String
  let clientID: String
  let isPreview: Bool
  let initialSSHTarget: String?

  var supportsManagedSSHTunnel: Bool {
    guard url.scheme?.lowercased() == "ws", url.port == Int(VoiceControlProtocol.defaultPort)
    else { return false }
    return ["127.0.0.1", "localhost", "::1"].contains(url.host?.lowercased() ?? "")
  }

  var screenSharingURL: URL? {
    guard let target = initialSSHTarget,
      let specification = try? SSHTunnelSpecification(target: target)
    else { return nil }
    var components = URLComponents()
    components.scheme = "vnc"
    components.host = specification.remoteHost
    return components.url
  }

  static func current(
    arguments: [String] = CommandLine.arguments,
    environment: [String: String] = ProcessInfo.processInfo.environment,
    environmentFileURL: URL = VoiceEnvironmentFile.defaultURL
  ) -> VoiceRemoteConfiguration {
    var resolvedEnvironment = (try? VoiceEnvironmentFile.load(from: environmentFileURL)) ?? [:]
    resolvedEnvironment.merge(environment) { _, processValue in processValue }
    var url = URL(
      string: resolvedEnvironment["CODEX_VOICE_REMOTE_URL"]
        ?? "ws://127.0.0.1:\(VoiceControlProtocol.defaultPort)/control"
    )!
    var tokenFile = resolvedEnvironment["CODEX_VOICE_TOKEN_FILE"].map {
      URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath).standardizedFileURL
    } ?? VoiceControlTokenStore.defaultURL
    var deviceName = resolvedEnvironment["CODEX_VOICE_DEVICE_NAME"] ?? "Mac mini"
    let initialSSHTarget = resolvedEnvironment["CODEX_VOICE_SSH_TARGET"]
    var isPreview = false

    var index = 1
    while index < arguments.count {
      switch arguments[index] {
      case "--url" where index + 1 < arguments.count:
        if let value = URL(string: arguments[index + 1]) { url = value }
        index += 1
      case "--token-file" where index + 1 < arguments.count:
        tokenFile = URL(fileURLWithPath: arguments[index + 1]).standardizedFileURL
        index += 1
      case "--device-name" where index + 1 < arguments.count:
        deviceName = arguments[index + 1]
        index += 1
      case "--preview":
        isPreview = true
      default:
        break
      }
      index += 1
    }

    let computerName = Host.current().localizedName ?? "macbook"
    return VoiceRemoteConfiguration(
      url: url,
      tokenFile: tokenFile,
      deviceName: deviceName,
      clientID: "\(computerName).codex-voice-menu",
      isPreview: isPreview,
      initialSSHTarget: initialSSHTarget
    )
  }
}
