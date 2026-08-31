import CodexVoiceCore
import Foundation

public enum PersistentVoiceControlClientError: LocalizedError {
  case notConnected
  case unexpectedMessage
  case serverRejected(String)
  case timedOut
  case connectionClosed

  public var errorDescription: String? {
    switch self {
    case .notConnected:
      return "La connexion au service vocal n'est pas ouverte."
    case .unexpectedMessage:
      return "Le service vocal a envoyé un message inattendu."
    case .serverRejected(let message):
      return message
    case .timedOut:
      return "Le service vocal n'a pas répondu dans le délai prévu."
    case .connectionClosed:
      return "La connexion au service vocal a été fermée."
    }
  }
}

public enum PersistentVoiceControlClientEvent: Sendable {
  case stateChanged(VoiceControlState)
  case disconnected(String)
}

public actor PersistentVoiceControlWebSocketClient {
  public typealias EventHandler = @Sendable (PersistentVoiceControlClientEvent) -> Void

  private let session: URLSession
  private let url: URL
  private let authorizationToken: String
  private let clientID: String
  private let requestTimeoutNanoseconds: UInt64

  private var sequence: UInt64
  private var socket: URLSessionWebSocketTask?
  private var receiveTask: Task<Void, Never>?
  private var eventHandler: EventHandler?
  private var pendingResponses: [
    UInt64: CheckedContinuation<VoiceControlMessage, Error>
  ] = [:]

  public init(
    url: URL,
    authorizationToken: String,
    clientID: String,
    requestTimeout: TimeInterval = 5,
    initialSequence: UInt64 = UInt64(Date().timeIntervalSince1970 * 1_000_000)
  ) {
    self.url = url
    self.authorizationToken = authorizationToken
    self.clientID = clientID
    requestTimeoutNanoseconds = UInt64(max(0.1, requestTimeout) * 1_000_000_000)
    sequence = max(1, initialSequence)

    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = requestTimeout
    configuration.timeoutIntervalForResource = 60 * 60 * 24
    session = URLSession(configuration: configuration)
  }

  public func connect(eventHandler: @escaping EventHandler) async throws -> VoiceControlState {
    self.eventHandler = eventHandler
    if socket == nil {
      var request = URLRequest(url: url)
      request.setValue(
        VoiceControlProtocol.webSocketSubprotocol,
        forHTTPHeaderField: "Sec-WebSocket-Protocol"
      )
      let task = session.webSocketTask(with: request)
      socket = task
      task.resume()
      receiveTask = Task { [weak self] in
        guard let self else { return }
        await self.receiveMessages(from: task)
      }
    }

    do {
      let response = try await send(.getState)
      guard let state = response.state else {
        throw PersistentVoiceControlClientError.unexpectedMessage
      }
      return state
    } catch {
      closeConnection(error: error, notify: false)
      throw error
    }
  }

  public func send(_ command: VoiceControlCommand) async throws -> VoiceControlMessage {
    guard let socket else { throw PersistentVoiceControlClientError.notConnected }
    sequence &+= 1
    if sequence == 0 { sequence = 1 }
    let request = VoiceControlRequest(
      clientID: clientID,
      sequence: sequence,
      authorization: authorizationToken,
      command: command
    )
    let payload = try JSONEncoder().encode(request)
    let currentSequence = sequence
    let timeout = requestTimeoutNanoseconds

    return try await withCheckedThrowingContinuation { continuation in
      pendingResponses[currentSequence] = continuation
      Task { [weak self] in
        do {
          try await socket.send(.data(payload))
        } catch {
          await self?.connectionFailed(error)
        }
      }
      Task { [weak self] in
        try? await Task.sleep(nanoseconds: timeout)
        await self?.requestTimedOut(currentSequence)
      }
    }
  }

  public func disconnect() {
    closeConnection(error: PersistentVoiceControlClientError.connectionClosed, notify: false)
    eventHandler = nil
  }

  private func receiveMessages(from task: URLSessionWebSocketTask) async {
    while !Task.isCancelled {
      do {
        let message = try await task.receive()
        let data: Data
        switch message {
        case .data(let value):
          data = value
        case .string(let value):
          data = Data(value.utf8)
        @unknown default:
          throw PersistentVoiceControlClientError.unexpectedMessage
        }
        try handle(data)
      } catch {
        guard !Task.isCancelled else { return }
        connectionFailed(error)
        return
      }
    }
  }

  private func handle(_ data: Data) throws {
    let message = try JSONDecoder().decode(VoiceControlMessage.self, from: data)
    guard message.version == VoiceControlProtocol.version else { return }

    if let state = message.state {
      eventHandler?(.stateChanged(state))
    }

    guard message.kind == .response, let responseSequence = message.sequence,
      let continuation = pendingResponses.removeValue(forKey: responseSequence)
    else { return }

    if message.status == .rejected {
      continuation.resume(
        throwing: PersistentVoiceControlClientError.serverRejected(
          message.error?.message ?? "Commande refusée."
        )
      )
    } else {
      continuation.resume(returning: message)
    }
  }

  private func requestTimedOut(_ requestSequence: UInt64) {
    guard let continuation = pendingResponses.removeValue(forKey: requestSequence) else { return }
    continuation.resume(throwing: PersistentVoiceControlClientError.timedOut)
  }

  private func connectionFailed(_ error: Error) {
    closeConnection(error: error, notify: true)
  }

  private func closeConnection(error: Error, notify: Bool) {
    guard let socket else { return }
    self.socket = nil
    receiveTask?.cancel()
    receiveTask = nil
    socket.cancel(with: .goingAway, reason: nil)

    let continuations = pendingResponses.values
    pendingResponses.removeAll()
    for continuation in continuations {
      continuation.resume(throwing: error)
    }

    if notify {
      eventHandler?(.disconnected(error.localizedDescription))
    }
  }
}
