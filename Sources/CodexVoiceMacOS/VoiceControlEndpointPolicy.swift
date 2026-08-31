import Foundation

public enum VoiceControlEndpointPolicy {
  public static func isAllowed(_ url: URL) -> Bool {
    switch url.scheme?.lowercased() {
    case "wss":
      return true
    case "ws":
      let host = url.host?.lowercased()
      return host == "127.0.0.1" || host == "localhost" || host == "::1"
    default:
      return false
    }
  }
}
