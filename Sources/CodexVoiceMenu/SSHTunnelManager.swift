import CodexVoiceMacOS
import Foundation

@MainActor
final class SSHTunnelManager {
  enum State: Equatable {
    case idle
    case starting
    case running
    case failed(String)
  }

  var stateHandler: ((State) -> Void)?

  private var specification: SSHTunnelSpecification?
  private var process: Process?
  private var restartTask: Task<Void, Never>?
  private var shouldRun = false

  private(set) var state: State = .idle {
    didSet { stateHandler?(state) }
  }

  func start(_ specification: SSHTunnelSpecification) {
    shouldRun = true
    self.specification = specification
    guard process == nil else { return }
    launch()
  }

  func stop() {
    shouldRun = false
    specification = nil
    restartTask?.cancel()
    restartTask = nil
    let runningProcess = process
    process = nil
    runningProcess?.terminate()
    state = .idle
  }

  private func launch() {
    guard shouldRun, process == nil, let specification else { return }
    state = .starting

    let process = Process()
    let errorPipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
    process.arguments = specification.arguments
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = FileHandle.nullDevice
    process.standardError = errorPipe
    process.terminationHandler = { [weak self] terminatedProcess in
      let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
      let errorText = String(decoding: errorData, as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines)
      Task { @MainActor [weak self] in
        self?.handleTermination(of: terminatedProcess, errorText: errorText)
      }
    }

    self.process = process
    do {
      try process.run()
      state = .running
    } catch {
      self.process = nil
      state = .failed(error.localizedDescription)
      scheduleRestart()
    }
  }

  private func handleTermination(of terminatedProcess: Process, errorText: String) {
    guard process === terminatedProcess else { return }
    process = nil
    guard shouldRun else {
      state = .idle
      return
    }
    state = .failed(Self.userMessage(for: errorText))
    scheduleRestart()
  }

  private func scheduleRestart() {
    guard shouldRun, restartTask == nil else { return }
    restartTask = Task { [weak self] in
      try? await Task.sleep(nanoseconds: 3_000_000_000)
      guard !Task.isCancelled, let self else { return }
      restartTask = nil
      launch()
    }
  }

  private static func userMessage(for errorText: String) -> String {
    let lowercased = errorText.lowercased()
    if lowercased.contains("permission denied") {
      return "Clé SSH refusée. Tester une connexion SSH manuelle vers le Mac mini."
    }
    if lowercased.contains("could not resolve hostname") {
      return "Mac mini introuvable sur le réseau local."
    }
    if lowercased.contains("address already in use") {
      return "Le port local 48731 est déjà utilisé."
    }
    if lowercased.contains("host key verification failed") {
      return "Identité SSH inconnue. Tester une connexion SSH manuelle une première fois."
    }
    return errorText.isEmpty ? "Le tunnel SSH s’est arrêté." : errorText
  }
}
