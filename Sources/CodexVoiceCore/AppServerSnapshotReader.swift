import Foundation

public enum AppServerSnapshotReaderError: LocalizedError {
  case processExited(Int32)
  case timeout(String)
  case invalidResponse(String)
  case rpc(String, Any)

  public var errorDescription: String? {
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

public final class AppServerSnapshotReader {
  private let executableURL: URL
  private let normalizer: AppServerSnapshotEventSource

  public init(executableURL: URL, normalizer: AppServerSnapshotEventSource = .init()) {
    self.executableURL = executableURL
    self.normalizer = normalizer
  }

  public func readRecentThreads(limit: Int) throws -> CodexEventBatch {
    guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
      throw AppServerSnapshotReaderError.invalidResponse(
        "binaire Codex introuvable : \(executableURL.path)"
      )
    }

    return try withClient { client in
      let list = try client.request(
        method: "thread/list",
        params: [
          "limit": max(1, limit),
          "sortKey": "updated_at",
          "sortDirection": "desc",
          "sourceKinds": ["cli", "vscode", "appServer", "unknown"],
        ]
      )
      let ids = (jsonArray(list["data"]) ?? []).compactMap {
        jsonObject($0).flatMap { jsonString($0["id"]) }
      }
      return readThreads(ids, using: client)
    }
  }

  public func readThreads(_ threadIDs: [String]) throws -> CodexEventBatch {
    guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
      throw AppServerSnapshotReaderError.invalidResponse(
        "binaire Codex introuvable : \(executableURL.path)"
      )
    }
    return try withClient { client in readThreads(threadIDs, using: client) }
  }

  private func withClient<T>(_ operation: (AppServerRPCProcess) throws -> T) throws -> T {
    let client = AppServerRPCProcess(executableURL: executableURL)
    try client.start()
    defer { client.stop() }
    try client.initialize()
    return try operation(client)
  }

  private func readThreads(
    _ threadIDs: [String],
    using client: AppServerRPCProcess
  ) -> CodexEventBatch {
    var batch = CodexEventBatch()
    for threadID in threadIDs {
      do {
        let result = try client.request(
          method: "thread/read",
          params: ["threadId": threadID, "includeTurns": true],
          timeout: 15
        )
        let data = try JSONSerialization.data(withJSONObject: result, options: [])
        let normalized = normalizer.normalize(threadReadData: data)
        batch.events.append(contentsOf: normalized.events)
        batch.diagnostics.append(contentsOf: normalized.diagnostics)
      } catch {
        batch.diagnostics.append(
          CodexIngestionDiagnostic(
            message:
              "Impossible de réconcilier la tâche \(threadID) : \(error.localizedDescription)"
          )
        )
      }
    }
    return batch
  }
}

private final class AppServerRPCProcess {
  private let executableURL: URL
  private let process = Process()
  private let inputPipe = Pipe()
  private let outputPipe = Pipe()
  private var outputBuffer = Data()
  private var messageQueue: [JSONObject] = []
  private var readerError: Error?
  private var reachedEOF = false
  private let readerCondition = NSCondition()
  private var nextRequestID = 1

  init(executableURL: URL) {
    self.executableURL = executableURL
  }

  func start() throws {
    process.executableURL = executableURL
    process.arguments = ["app-server", "--stdio"]
    process.standardInput = inputPipe
    process.standardOutput = outputPipe
    process.standardError = FileHandle.nullDevice
    outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
      self?.consume(handle.availableData)
    }
    process.terminationHandler = { [weak self] _ in
      guard let self else { return }
      readerCondition.lock()
      reachedEOF = true
      readerCondition.broadcast()
      readerCondition.unlock()
    }
    try process.run()
  }

  func initialize() throws {
    _ = try request(
      method: "initialize",
      params: [
        "clientInfo": [
          "name": "codex_voice_core",
          "title": "Codex Voice Core",
          "version": "0.1.0",
        ],
        "capabilities": ["experimentalApi": true],
      ]
    )
    try send(["method": "initialized", "params": [:]])
  }

  func request(
    method: String,
    params: JSONObject = [:],
    timeout: TimeInterval = 30
  ) throws -> JSONObject {
    let requestID = nextRequestID
    nextRequestID += 1
    try send(["method": method, "id": requestID, "params": params])

    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      guard let message = try readMessage(until: deadline) else {
        if !process.isRunning {
          throw AppServerSnapshotReaderError.processExited(process.terminationStatus)
        }
        continue
      }
      guard let responseID = (message["id"] as? NSNumber)?.intValue,
        responseID == requestID
      else { continue }
      if let error = message["error"] {
        throw AppServerSnapshotReaderError.rpc(method, error)
      }
      guard let result = jsonObject(message["result"]) else {
        throw AppServerSnapshotReaderError.invalidResponse("résultat absent pour \(method)")
      }
      return result
    }
    throw AppServerSnapshotReaderError.timeout(method)
  }

  func stop() {
    try? inputPipe.fileHandleForWriting.close()
    let deadline = Date().addingTimeInterval(1)
    while process.isRunning, Date() < deadline {
      Thread.sleep(forTimeInterval: 0.02)
    }
    if process.isRunning { process.terminate() }
    outputPipe.fileHandleForReading.readabilityHandler = nil
  }

  private func send(_ message: JSONObject) throws {
    let data = try JSONSerialization.data(withJSONObject: message, options: [])
    try inputPipe.fileHandleForWriting.write(contentsOf: data)
    try inputPipe.fileHandleForWriting.write(contentsOf: Data([0x0A]))
  }

  private func readMessage(until deadline: Date) throws -> JSONObject? {
    readerCondition.lock()
    defer { readerCondition.unlock() }
    while messageQueue.isEmpty, readerError == nil, !reachedEOF {
      if !readerCondition.wait(until: deadline) { return nil }
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
    while let newline = outputBuffer.firstIndex(of: 0x0A) {
      var line = Data(outputBuffer[..<newline])
      outputBuffer.removeSubrange(...newline)
      if line.last == 0x0D { line.removeLast() }
      guard !line.isEmpty else { continue }
      do {
        guard let message = try JSONSerialization.jsonObject(with: line) as? JSONObject else {
          throw AppServerSnapshotReaderError.invalidResponse("la ligne JSON n'est pas un objet")
        }
        messageQueue.append(message)
      } catch {
        readerError = error
        return
      }
    }
  }
}
