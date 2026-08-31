import Foundation

private struct PersistedProbeState: Codable {
  let schemaVersion: Int
  let updatedAt: String
  let seenItems: [String]
}

final class ProbeCheckpointStore {
  private(set) var seenItems: Set<String>
  let fileURL: URL?

  init(fileURL: URL?) throws {
    self.fileURL = fileURL
    guard let fileURL, FileManager.default.fileExists(atPath: fileURL.path) else {
      seenItems = []
      return
    }

    let data = try Data(contentsOf: fileURL)
    let state = try JSONDecoder().decode(PersistedProbeState.self, from: data)
    seenItems = Set(state.seenItems)
  }

  @discardableResult
  func observe(_ key: String) -> Bool {
    seenItems.insert(key).inserted
  }

  func save() throws {
    guard let fileURL else { return }
    let directory = fileURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let state = PersistedProbeState(
      schemaVersion: 1,
      updatedAt: isoTimestamp(),
      seenItems: seenItems.sorted()
    )
    let data = try JSONEncoder().encode(state)
    try data.write(to: fileURL, options: .atomic)
  }
}

struct HistoryAnalysis {
  var threadsRead = 0
  var turns = 0
  var userMessages = 0
  var assistantMessages = 0
  var otherItems = 0
  var newlyObserved = 0
  var alreadyKnown = 0
  var phaseCounts: [String: Int] = [:]
  var finalTurnStatusCounts: [String: Int] = [:]

  var asJSON: JSONObject {
    [
      "threadsRead": threadsRead,
      "turns": turns,
      "userMessages": userMessages,
      "assistantMessages": assistantMessages,
      "otherItems": otherItems,
      "newlyObserved": newlyObserved,
      "alreadyKnown": alreadyKnown,
      "phaseCounts": phaseCounts,
      "turnStatusCounts": finalTurnStatusCounts,
    ]
  }
}

enum HistoryAnalyzer {
  static func analyze(
    thread: JSONObject,
    checkpointStore: ProbeCheckpointStore
  ) -> HistoryAnalysis {
    var result = HistoryAnalysis(threadsRead: 1)
    let threadID = string(thread["id"]) ?? "unknown-thread"

    for turnValue in array(thread["turns"]) ?? [] {
      guard let turn = object(turnValue) else { continue }
      result.turns += 1
      let turnID = string(turn["id"]) ?? "unknown-turn"
      let status = string(turn["status"]) ?? "unknown"
      result.finalTurnStatusCounts[status, default: 0] += 1

      for itemValue in array(turn["items"]) ?? [] {
        guard let item = object(itemValue) else { continue }
        let type = string(item["type"]) ?? "unknown"
        switch type {
        case "userMessage":
          result.userMessages += 1
        case "agentMessage":
          result.assistantMessages += 1
          let phase = string(item["phase"]) ?? "missing"
          result.phaseCounts[phase, default: 0] += 1
        default:
          result.otherItems += 1
        }

        guard type == "userMessage" || type == "agentMessage" else { continue }
        let itemID = string(item["id"]) ?? canonicalDigest(item)
        let key = "\(threadID)|\(turnID)|\(itemID)|\(canonicalDigest(item))"
        if checkpointStore.observe(key) {
          result.newlyObserved += 1
        } else {
          result.alreadyKnown += 1
        }
      }
    }

    return result
  }
}

func += (lhs: inout HistoryAnalysis, rhs: HistoryAnalysis) {
  lhs.threadsRead += rhs.threadsRead
  lhs.turns += rhs.turns
  lhs.userMessages += rhs.userMessages
  lhs.assistantMessages += rhs.assistantMessages
  lhs.otherItems += rhs.otherItems
  lhs.newlyObserved += rhs.newlyObserved
  lhs.alreadyKnown += rhs.alreadyKnown
  for (phase, count) in rhs.phaseCounts {
    lhs.phaseCounts[phase, default: 0] += count
  }
  for (status, count) in rhs.finalTurnStatusCounts {
    lhs.finalTurnStatusCounts[status, default: 0] += count
  }
}
