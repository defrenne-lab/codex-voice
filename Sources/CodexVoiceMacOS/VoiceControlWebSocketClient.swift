import CodexVoiceCore
import Foundation

public enum VoiceControlWebSocketClientError: LocalizedError {
  case unexpectedMessage
  case responseLimitReached
  case serverRejected(String)
  case timedOut

  public var errorDescription: String? {
    switch self {
    case .unexpectedMessage: return "Le serveur a envoyé un message WebSocket inattendu."
    case .responseLimitReached: return "La réponse attendue n'a pas été reçue."
    case .serverRejected(let message): return message
    case .timedOut: return "Le serveur de contrôle n'a pas répondu dans le délai prévu."
    }
  }
}

public final class VoiceControlWebSocketClient: @unchecked Sendable {
  private let session: URLSession
  private let timeoutNanoseconds: UInt64

  public init(timeout: TimeInterval = 5) {
    timeoutNanoseconds = UInt64(max(0.1, timeout) * 1_000_000_000)
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = timeout
    configuration.timeoutIntervalForResource = timeout
    session = URLSession(configuration: configuration)
  }

  public func perform(
    _ request: VoiceControlRequest,
    at url: URL
  ) async throws -> VoiceControlMessage {
    var urlRequest = URLRequest(url: url)
    urlRequest.setValue(
      VoiceControlProtocol.webSocketSubprotocol,
      forHTTPHeaderField: "Sec-WebSocket-Protocol"
    )
    let task = session.webSocketTask(with: urlRequest)
    task.resume()
    defer { task.cancel(with: .normalClosure, reason: nil) }

    return try await withTaskCancellationHandler {
      try await withThrowingTaskGroup(of: VoiceControlMessage.self) { group in
        group.addTask { [self] in
          try await withTaskCancellationHandler {
            try await exchange(request, using: task)
          } onCancel: {
            task.cancel(with: .goingAway, reason: nil)
          }
        }
        group.addTask { [timeoutNanoseconds] in
          try await Task.sleep(nanoseconds: timeoutNanoseconds)
          throw VoiceControlWebSocketClientError.timedOut
        }
        guard let result = try await group.next() else {
          throw VoiceControlWebSocketClientError.unexpectedMessage
        }
        group.cancelAll()
        return result
      }
    } onCancel: {
      task.cancel(with: .goingAway, reason: nil)
    }
  }

  private func exchange(
    _ request: VoiceControlRequest,
    using task: URLSessionWebSocketTask
  ) async throws -> VoiceControlMessage {
    let payload = try JSONEncoder().encode(request)
    try await task.send(.data(payload))

    for _ in 0..<32 {
      let received = try await task.receive()
      let data: Data
      switch received {
      case .data(let value):
        data = value
      case .string(let value):
        data = Data(value.utf8)
      @unknown default:
        throw VoiceControlWebSocketClientError.unexpectedMessage
      }
      let message = try JSONDecoder().decode(VoiceControlMessage.self, from: data)
      guard message.version == VoiceControlProtocol.version else { continue }
      guard message.kind == .response,
        message.clientID == request.clientID,
        message.sequence == request.sequence
      else { continue }
      if message.status == .rejected {
        throw VoiceControlWebSocketClientError.serverRejected(
          message.error?.message ?? "Commande refusée."
        )
      }
      return message
    }
    throw VoiceControlWebSocketClientError.responseLimitReached
  }
}
