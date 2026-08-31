import CodexVoiceCore
import Dispatch
import Foundation
@preconcurrency import Network

public enum VoiceControlServerEvent: Sendable {
  case ready(port: UInt16)
  case clientConnected
  case clientDisconnected
  case commandReceived(VoiceControlCommandKind)
  case responseSent(VoiceControlResponseStatus)
  case failed(String)
}

public final class VoiceControlWebSocketServer: @unchecked Sendable {
  private final class Client: @unchecked Sendable {
    let id = UUID()
    let connection: NWConnection
    var isAuthenticated = false

    init(connection: NWConnection) {
      self.connection = connection
    }
  }

  private let service: VoiceControlService
  private let queue = DispatchQueue(label: "lab.defrenne.codexvoice3.control-server")
  private var listener: NWListener?
  private var clients: [UUID: Client] = [:]

  public var eventHandler: (@Sendable (VoiceControlServerEvent) -> Void)?

  public init(service: VoiceControlService) {
    self.service = service
  }

  public func start(port: UInt16 = VoiceControlProtocol.defaultPort) throws {
    guard listener == nil else { return }
    guard let networkPort = NWEndpoint.Port(rawValue: port) else {
      throw VoiceControlWebSocketServerError.invalidPort(port)
    }

    let webSocket = NWProtocolWebSocket.Options(.version13)
    webSocket.autoReplyPing = true
    webSocket.maximumMessageSize = VoiceControlProtocol.maximumMessageBytes
    webSocket.setClientRequestHandler(queue) { subprotocols, _ in
      guard subprotocols.contains(VoiceControlProtocol.webSocketSubprotocol) else {
        return NWProtocolWebSocket.Response(status: .reject, subprotocol: nil)
      }
      return NWProtocolWebSocket.Response(
        status: .accept,
        subprotocol: VoiceControlProtocol.webSocketSubprotocol
      )
    }

    let parameters = NWParameters(tls: nil, tcp: NWProtocolTCP.Options())
    parameters.allowLocalEndpointReuse = true
    parameters.defaultProtocolStack.applicationProtocols.insert(webSocket, at: 0)
    parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: networkPort)

    let listener = try NWListener(using: parameters)
    listener.stateUpdateHandler = { [weak self, weak listener] state in
      guard let self else { return }
      switch state {
      case .ready:
        let actualPort = listener?.port?.rawValue ?? port
        self.eventHandler?(.ready(port: actualPort))
      case .failed(let error):
        self.eventHandler?(.failed(error.localizedDescription))
      default:
        break
      }
    }
    listener.newConnectionHandler = { [weak self] connection in
      self?.accept(connection)
    }
    self.listener = listener
    listener.start(queue: queue)
  }

  public func stop() {
    queue.async { [weak self] in
      guard let self else { return }
      self.listener?.cancel()
      self.listener = nil
      for client in self.clients.values { client.connection.cancel() }
      self.clients.removeAll()
    }
  }

  public func publishState() {
    Task { @MainActor [weak self] in
      guard let self else { return }
      let message = self.service.stateChangedMessage()
      guard let data = try? JSONEncoder().encode(message) else { return }
      self.queue.async { [weak self] in
        guard let self else { return }
        for client in self.clients.values where client.isAuthenticated {
          self.send(data, to: client)
        }
      }
    }
  }

  private func accept(_ connection: NWConnection) {
    let client = Client(connection: connection)
    clients[client.id] = client
    connection.stateUpdateHandler = { [weak self, weak client] state in
      guard let self, let client else { return }
      switch state {
      case .ready:
        self.eventHandler?(.clientConnected)
        self.receiveNext(from: client)
      case .failed, .cancelled:
        self.remove(client)
      default:
        break
      }
    }
    connection.start(queue: queue)
  }

  private func receiveNext(from client: Client) {
    client.connection.receiveMessage { [weak self, weak client] data, _, _, error in
      guard let self, let client else { return }
      if error != nil {
        self.remove(client)
        return
      }
      guard let data, !data.isEmpty else {
        self.receiveNext(from: client)
        return
      }
      guard data.count <= VoiceControlProtocol.maximumMessageBytes else {
        self.sendProtocolError(code: "messageTooLarge", to: client)
        return
      }
      guard let request = try? JSONDecoder().decode(VoiceControlRequest.self, from: data) else {
        self.sendProtocolError(code: "invalidJSON", to: client)
        return
      }
      self.eventHandler?(.commandReceived(request.command.kind))

      Task { @MainActor [weak self, weak client] in
        guard let self, let client else { return }
        let result = self.service.handle(request)
        guard let response = try? JSONEncoder().encode(result.message) else { return }
        self.queue.async { [weak self, weak client] in
          guard let self, let client else { return }
          if result.isAuthenticated { client.isAuthenticated = true }
          self.send(response, to: client) { [weak self, weak client] in
            guard let self, let client else { return }
            self.eventHandler?(.responseSent(result.message.status ?? .rejected))
            self.receiveNext(from: client)
          }
        }
      }
    }
  }

  private func sendProtocolError(code: String, to client: Client) {
    let message = VoiceControlMessage(
      kind: .response,
      status: .rejected,
      error: VoiceControlErrorPayload(code: code, message: "Message de contrôle invalide.")
    )
    guard let data = try? JSONEncoder().encode(message) else {
      remove(client)
      return
    }
    send(data, to: client) { [weak self, weak client] in
      guard let self, let client else { return }
      self.receiveNext(from: client)
    }
  }

  private func send(
    _ data: Data,
    to client: Client,
    completion: (@Sendable () -> Void)? = nil
  ) {
    let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
    let context = NWConnection.ContentContext(
      identifier: "codex-voice-control",
      metadata: [metadata]
    )
    client.connection.send(
      content: data,
      contentContext: context,
      isComplete: true,
      completion: .contentProcessed { [weak self, weak client] error in
        guard let self, let client else { return }
        if let error {
          self.eventHandler?(.failed(error.localizedDescription))
          self.remove(client)
        } else {
          completion?()
        }
      }
    )
  }

  private func remove(_ client: Client) {
    guard clients.removeValue(forKey: client.id) != nil else { return }
    client.connection.cancel()
    eventHandler?(.clientDisconnected)
  }
}

public enum VoiceControlWebSocketServerError: LocalizedError {
  case invalidPort(UInt16)

  public var errorDescription: String? {
    switch self {
    case .invalidPort(let port): return "Port de contrôle invalide : \(port)"
    }
  }
}
