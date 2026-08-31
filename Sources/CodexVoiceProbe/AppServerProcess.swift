import Foundation

enum ProbeTransport: String {
  case auto
  case daemon
  case standalone
}

enum AppServerClientError: LocalizedError {
  case processExited(Int32)
  case timeout(String)
  case invalidResponse(String)
  case rpc(String, Any)

  var errorDescription: String? {
    switch self {
    case .processExited(let status):
      return "Le processus App Server s'est arrêté avec le statut \(status)."
    case .timeout(let method):
      return "Délai dépassé en attendant la réponse à \(method)."
    case .invalidResponse(let message):
      return "Réponse App Server invalide : \(message)"
    case .rpc(let method, let error):
      return "Erreur App Server pour \(method) : \(error)"
    }
  }
}

final class AppServerProcess {
  typealias NotificationHandler = (JSONObject) -> Void

  private let executableURL: URL
  private let transport: ProbeTransport
  private let socketPath: String
  private let notificationHandler: NotificationHandler
  private let process = Process()
  private let inputPipe = Pipe()
  private let outputPipe = Pipe()
  private var outputBuffer = Data()
  private var messageQueue: [JSONObject] = []
  private var readerError: Error?
  private var reachedEOF = false
  private let readerCondition = NSCondition()
  private var nextRequestID = 1

  init(
    executableURL: URL,
    transport: ProbeTransport,
    socketPath: String,
    notificationHandler: @escaping NotificationHandler
  ) {
    self.executableURL = executableURL
    self.transport = transport
    self.socketPath = socketPath
    self.notificationHandler = notificationHandler
  }

  func start() throws {
    process.executableURL = executableURL
    switch transport {
    case .standalone:
      process.arguments = ["app-server", "--stdio"]
    case .daemon:
      process.arguments = ["app-server", "proxy", "--sock", socketPath]
    case .auto:
      preconditionFailure("Le transport auto doit être résolu avant le démarrage.")
    }
    process.standardInput = inputPipe
    process.standardOutput = outputPipe
    process.standardError = FileHandle.standardError
    outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
      self?.consume(handle.availableData)
    }
    process.terminationHandler = { [weak self] _ in
      guard let self else { return }
      self.readerCondition.lock()
      self.reachedEOF = true
      self.readerCondition.broadcast()
      self.readerCondition.unlock()
    }
    try process.run()
  }

  func initialize(timeout: TimeInterval = 30) throws -> JSONObject {
    let response = try request(
      method: "initialize",
      params: [
        "clientInfo": [
          "name": "codex_voice_probe",
          "title": "Codex Voice App Server Probe",
          "version": "0.1.0",
        ],
        "capabilities": [
          "experimentalApi": true
        ],
      ],
      timeout: timeout
    )
    try notify(method: "initialized", params: [:])
    return response
  }

  func request(method: String, params: JSONObject = [:], timeout: TimeInterval = 45) throws
    -> JSONObject
  {
    let requestID = nextRequestID
    nextRequestID += 1
    try send([
      "method": method,
      "id": requestID,
      "params": params,
    ])

    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      guard let message = try readMessage(until: deadline) else {
        if !process.isRunning {
          throw AppServerClientError.processExited(process.terminationStatus)
        }
        continue
      }

      if let responseID = integer(message["id"]), responseID == requestID {
        if let rpcError = message["error"] {
          throw AppServerClientError.rpc(method, rpcError)
        }
        guard let result = object(message["result"]) else {
          throw AppServerClientError.invalidResponse("résultat absent pour \(method)")
        }
        return result
      }

      notificationHandler(message)
    }

    throw AppServerClientError.timeout(method)
  }

  func notify(method: String, params: JSONObject = [:]) throws {
    try send([
      "method": method,
      "params": params,
    ])
  }

  @discardableResult
  func receive(timeout: TimeInterval) throws -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    guard let message = try readMessage(until: deadline) else {
      if !process.isRunning {
        throw AppServerClientError.processExited(process.terminationStatus)
      }
      return false
    }
    notificationHandler(message)
    return true
  }

  func stop() {
    try? inputPipe.fileHandleForWriting.close()

    let deadline = Date().addingTimeInterval(2)
    while process.isRunning, Date() < deadline {
      Thread.sleep(forTimeInterval: 0.05)
    }
    if process.isRunning {
      process.terminate()
    }
    outputPipe.fileHandleForReading.readabilityHandler = nil
  }

  private func send(_ message: JSONObject) throws {
    let data = try JSONSerialization.data(withJSONObject: message, options: [])
    inputPipe.fileHandleForWriting.write(data)
    inputPipe.fileHandleForWriting.write(Data([0x0A]))
  }

  private func readMessage(until deadline: Date) throws -> JSONObject? {
    readerCondition.lock()
    defer { readerCondition.unlock() }

    while messageQueue.isEmpty, readerError == nil, !reachedEOF {
      if !readerCondition.wait(until: deadline) {
        return nil
      }
    }

    if let readerError { throw readerError }
    if !messageQueue.isEmpty { return messageQueue.removeFirst() }
    return nil
  }

  private func consume(_ data: Data) {
    readerCondition.lock()
    defer {
      readerCondition.broadcast()
      readerCondition.unlock()
    }

    guard !data.isEmpty else {
      reachedEOF = true
      return
    }

    outputBuffer.append(data)
    while let line = popLine() {
      guard !line.isEmpty else { continue }
      do {
        let value = try JSONSerialization.jsonObject(with: line)
        guard let message = value as? JSONObject else {
          throw AppServerClientError.invalidResponse("la ligne JSON n'est pas un objet")
        }
        messageQueue.append(message)
      } catch {
        readerError = error
        return
      }
    }
  }

  private func popLine() -> Data? {
    guard let newlineIndex = outputBuffer.firstIndex(of: 0x0A) else { return nil }
    var line = outputBuffer[..<newlineIndex]
    if line.last == 0x0D {
      line = line.dropLast()
    }
    outputBuffer.removeSubrange(...newlineIndex)
    return Data(line)
  }
}
