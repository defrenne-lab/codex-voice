import Foundation

struct ThreadDescriptor {
  let id: String
  let name: String?
  let preview: String?
  let status: String
  let cwd: String?

  init?(_ object: JSONObject) {
    guard let id = string(object["id"]) else { return nil }
    self.id = id
    name = string(object["name"])
    preview = string(object["preview"])
    status = ProbeRunner.statusName(from: object["status"])
    cwd = string(object["cwd"])
  }

  var displayName: String {
    if let name, !name.isEmpty { return name }
    if let preview, !preview.isEmpty { return clipped(preview, limit: 72) }
    return "Sans titre"
  }

  var asJSON: JSONObject {
    var value: JSONObject = [
      "id": id,
      "displayName": displayName,
      "status": status,
    ]
    if let name { value["name"] = name }
    if let cwd { value["cwd"] = cwd }
    return value
  }
}

final class ProbeRunner {
  private let options: CLIOptions
  private let checkpointStore: ProbeCheckpointStore
  private let recorder: EventRecorder
  private var subscribedThreadIDs: [String] = []

  init(options: CLIOptions) throws {
    self.options = options
    let stateURL = options.statePath.map {
      URL(
        fileURLWithPath: $0,
        relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
      ).standardizedFileURL
    }
    checkpointStore = try ProbeCheckpointStore(fileURL: stateURL)
    recorder = EventRecorder(includeText: options.includeText, checkpointStore: checkpointStore)
  }

  func run() throws {
    let transport = options.resolvedTransport()
    let executableURL = URL(fileURLWithPath: options.codexPath)
    guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
      throw CLIError.invalidArgument("binaire Codex introuvable : \(executableURL.path)")
    }

    print("Codex Voice · sonde App Server")
    print("Transport : \(transport.rawValue)")
    print("Audio : désactivé par conception")

    let client = AppServerProcess(
      executableURL: executableURL,
      transport: transport,
      socketPath: options.socketPath,
      notificationHandler: { [weak self] message in self?.recorder.record(message) }
    )
    try client.start()
    defer { client.stop() }

    let initialized = try client.initialize()
    let userAgent = string(initialized["userAgent"]) ?? "inconnu"
    print("Serveur : \(userAgent)")

    let listResult = try client.request(
      method: "thread/list",
      params: [
        "limit": options.limit,
        "sortKey": "updated_at",
        "sortDirection": "desc",
        "sourceKinds": ["cli", "vscode", "appServer", "unknown"],
      ]
    )
    let threads = (array(listResult["data"]) ?? [])
      .compactMap(object)
      .compactMap(ThreadDescriptor.init)

    print("Tâches trouvées : \(threads.count)")
    for thread in threads {
      print("  \(shortID(thread.id))  [\(thread.status)]  \(thread.displayName)")
    }

    let historyIDs = selectedIDs(
      explicit: options.explicitThreadIDs,
      recent: Array(threads.prefix(options.historyRecent)).map(\.id)
    )
    var historyAnalysis = HistoryAnalysis()
    var readErrors: [JSONObject] = []

    for threadID in historyIDs {
      do {
        let readResult = try client.request(
          method: "thread/read",
          params: ["threadId": threadID, "includeTurns": true]
        )
        guard let thread = object(readResult["thread"]) else {
          throw AppServerClientError.invalidResponse("thread/read sans thread")
        }
        historyAnalysis += HistoryAnalyzer.analyze(thread: thread, checkpointStore: checkpointStore)
      } catch {
        readErrors.append(["threadId": threadID, "error": error.localizedDescription])
        print("  lecture impossible \(shortID(threadID)) : \(error.localizedDescription)")
      }
    }

    print(
      "Historique : \(historyAnalysis.turns) tours, "
        + "\(historyAnalysis.userMessages) messages utilisateur, "
        + "\(historyAnalysis.assistantMessages) messages agent"
    )
    print("Phases historiques : \(historyAnalysis.phaseCounts)")
    print(
      "Checkpoint : \(historyAnalysis.newlyObserved) nouveaux, \(historyAnalysis.alreadyKnown) déjà connus"
    )

    var subscriptionErrors: [JSONObject] = []
    if options.command == .watch {
      let recentIDs = Array(threads.prefix(options.subscribeRecent)).map(\.id)
      let subscriptionIDs = selectedIDs(explicit: options.explicitThreadIDs, recent: recentIDs)
      for threadID in subscriptionIDs {
        do {
          _ = try client.request(method: "thread/resume", params: ["threadId": threadID])
          subscribedThreadIDs.append(threadID)
          print("Abonnement : \(shortID(threadID))")
        } catch {
          subscriptionErrors.append(["threadId": threadID, "error": error.localizedDescription])
          print("Abonnement impossible \(shortID(threadID)) : \(error.localizedDescription)")
        }
      }

      print("Écoute pendant \(Int(options.watchSeconds)) secondes…")
      let deadline = Date().addingTimeInterval(options.watchSeconds)
      while Date() < deadline {
        _ = try client.receive(timeout: min(1, max(0, deadline.timeIntervalSinceNow)))
      }

      for threadID in subscribedThreadIDs {
        do {
          _ = try client.request(
            method: "thread/unsubscribe", params: ["threadId": threadID], timeout: 10)
        } catch {
          print("Désabonnement incomplet \(shortID(threadID)) : \(error.localizedDescription)")
        }
      }
    }

    try checkpointStore.save()

    var report: JSONObject = [
      "schemaVersion": 1,
      "createdAt": isoTimestamp(),
      "command": options.command.rawValue,
      "transport": transport.rawValue,
      "codexPath": executableURL.path,
      "userAgent": userAgent,
      "threads": threads.map(\.asJSON),
      "history": historyAnalysis.asJSON,
      "readErrors": readErrors,
      "subscriptions": [
        "succeeded": subscribedThreadIDs,
        "errors": subscriptionErrors,
      ],
      "live": recorder.asJSON,
      "audioProduced": false,
    ]
    if let statePath = options.statePath { report["statePath"] = statePath }

    if let outputPath = options.outputPath {
      let outputURL = URL(
        fileURLWithPath: outputPath,
        relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
      ).standardizedFileURL
      try writeJSON(report, to: outputURL)
      print("Rapport : \(outputURL.path)")
    }

    print("Terminé. Aucun message envoyé et aucun son produit.")
  }

  static func statusName(from value: Any?) -> String {
    if let status = string(value) { return status }
    if let status = object(value) { return string(status["type"]) ?? "unknown" }
    return "unknown"
  }

  private func selectedIDs(explicit: [String], recent: [String]) -> [String] {
    var seen: Set<String> = []
    return (explicit + recent).filter { seen.insert($0).inserted }
  }
}
