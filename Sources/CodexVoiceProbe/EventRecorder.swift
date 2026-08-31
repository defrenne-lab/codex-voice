import Foundation

final class EventRecorder {
  private let includeText: Bool
  private let checkpointStore: ProbeCheckpointStore

  private(set) var methodCounts: [String: Int] = [:]
  private(set) var phaseCounts: [String: Int] = [:]
  private(set) var stableItemsNew = 0
  private(set) var stableItemsKnown = 0
  private(set) var lastUserThreadID: String?
  private(set) var records: [JSONObject] = []

  init(includeText: Bool, checkpointStore: ProbeCheckpointStore) {
    self.includeText = includeText
    self.checkpointStore = checkpointStore
  }

  func record(_ message: JSONObject) {
    guard let method = string(message["method"]) else {
      if message["id"] != nil {
        print("[réponse non sollicitée] \(message)")
      }
      return
    }

    methodCounts[method, default: 0] += 1
    let params = object(message["params"]) ?? [:]
    let threadID =
      string(params["threadId"])
      ?? object(params["thread"]).flatMap { string($0["id"]) }
    let turnID =
      string(params["turnId"])
      ?? object(params["turn"]).flatMap { string($0["id"]) }

    var detail: JSONObject = [
      "timestamp": isoTimestamp(),
      "method": method,
    ]
    if let threadID { detail["threadId"] = threadID }
    if let turnID { detail["turnId"] = turnID }

    switch method {
    case "item/started", "item/completed":
      if let item = object(params["item"]) {
        let itemID = string(item["id"]) ?? string(params["itemId"])
        let type = string(item["type"]) ?? "unknown"
        let phase = string(item["phase"]) ?? "missing"
        detail["itemId"] = itemID ?? NSNull()
        detail["itemType"] = type
        if type == "agentMessage" {
          detail["phase"] = phase
          phaseCounts[phase, default: 0] += 1
        }

        if let text = string(item["text"]) {
          detail["textLength"] = text.count
          if includeText { detail["textPreview"] = clipped(text) }
        }

        if method == "item/completed", let threadID, let turnID {
          let stableID = itemID ?? canonicalDigest(item)
          let key = "\(threadID)|\(turnID)|\(stableID)|\(canonicalDigest(item))"
          if checkpointStore.observe(key) {
            stableItemsNew += 1
            detail["checkpoint"] = "new"
          } else {
            stableItemsKnown += 1
            detail["checkpoint"] = "known"
          }
          if type == "userMessage" {
            lastUserThreadID = threadID
          }
        }
      }

    case "item/agentMessage/delta":
      if let delta = string(params["delta"]) {
        detail["deltaLength"] = delta.count
        if includeText { detail["deltaPreview"] = clipped(delta) }
      }
      if let itemID = string(params["itemId"]) { detail["itemId"] = itemID }

    case "turn/completed":
      if let turn = object(params["turn"]), let status = string(turn["status"]) {
        detail["status"] = status
      }

    case "thread/name/updated":
      if let name = string(params["name"]) { detail["name"] = name }

    case "thread/status/changed":
      if let status = object(params["status"]), let type = string(status["type"]) {
        detail["status"] = type
      }

    case "remoteControl/status/changed":
      if let status = string(params["status"]) { detail["status"] = status }

    default:
      break
    }

    if records.count < 2_000 {
      records.append(detail)
    }
    print(summary(for: detail))
  }

  var asJSON: JSONObject {
    var result: JSONObject = [
      "methodCounts": methodCounts,
      "phaseCounts": phaseCounts,
      "stableItemsNew": stableItemsNew,
      "stableItemsKnown": stableItemsKnown,
      "events": records,
    ]
    if let lastUserThreadID { result["lastUserThreadId"] = lastUserThreadID }
    return result
  }

  private func summary(for detail: JSONObject) -> String {
    let method = string(detail["method"]) ?? "événement"
    var parts = ["[\(method)]"]
    if let threadID = string(detail["threadId"]) { parts.append("thread=\(shortID(threadID))") }
    if let type = string(detail["itemType"]) { parts.append("item=\(type)") }
    if let phase = string(detail["phase"]) { parts.append("phase=\(phase)") }
    if let status = string(detail["status"]) { parts.append("status=\(status)") }
    if let length = integer(detail["deltaLength"]) { parts.append("delta=\(length)c") }
    if let length = integer(detail["textLength"]) { parts.append("texte=\(length)c") }
    if let preview = string(detail["textPreview"]) ?? string(detail["deltaPreview"]) {
      parts.append("« \(preview) »")
    }
    return parts.joined(separator: " ")
  }
}
