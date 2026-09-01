import CodexVoiceCore
import Foundation

public enum SSHTunnelSpecificationError: LocalizedError, Equatable {
  case invalidTarget
  case invalidPort

  public var errorDescription: String? {
    switch self {
    case .invalidTarget:
      return "La cible SSH doit ressembler à utilisateur@mac-mini.local."
    case .invalidPort:
      return "Le port du tunnel SSH est invalide."
    }
  }
}

public struct SSHTunnelSpecification: Equatable, Sendable {
  public let target: String
  public let localPort: UInt16
  public let remotePort: UInt16

  public init(
    target: String,
    localPort: Int = Int(VoiceControlProtocol.defaultPort),
    remotePort: Int = Int(VoiceControlProtocol.defaultPort)
  ) throws {
    let target = target.trimmingCharacters(in: .whitespacesAndNewlines)
    guard Self.isValidTarget(target) else {
      throw SSHTunnelSpecificationError.invalidTarget
    }
    guard let localPort = UInt16(exactly: localPort), localPort > 0,
      let remotePort = UInt16(exactly: remotePort), remotePort > 0
    else {
      throw SSHTunnelSpecificationError.invalidPort
    }
    self.target = target
    self.localPort = localPort
    self.remotePort = remotePort
  }

  public var arguments: [String] {
    [
      "-o", "BatchMode=yes",
      "-o", "PreferredAuthentications=publickey",
      "-o", "PasswordAuthentication=no",
      "-o", "KbdInteractiveAuthentication=no",
      "-o", "ExitOnForwardFailure=yes",
      "-o", "ServerAliveInterval=30",
      "-o", "ServerAliveCountMax=3",
      "-o", "ConnectTimeout=8",
      "-o", "ClearAllForwardings=no",
      "-o", "LogLevel=ERROR",
      "-T",
      "-N",
      "-L", "127.0.0.1:\(localPort):127.0.0.1:\(remotePort)",
      target,
    ]
  }

  private static func isValidTarget(_ target: String) -> Bool {
    guard !target.isEmpty, target.first != "-", target.count <= 255 else { return false }
    let parts = target.split(separator: "@", omittingEmptySubsequences: false)
    guard parts.count == 1 || parts.count == 2, parts.allSatisfy({ !$0.isEmpty }) else {
      return false
    }
    return target.unicodeScalars.allSatisfy { scalar in
      CharacterSet.alphanumerics.contains(scalar)
        || scalar == "." || scalar == "-" || scalar == "_" || scalar == "@"
    }
  }
}
