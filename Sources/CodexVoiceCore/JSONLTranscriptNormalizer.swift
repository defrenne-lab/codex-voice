import Foundation

public final class JSONLTranscriptNormalizer {
  public private(set) var threadID: String?
  public private(set) var currentTurnID: String?
  public private(set) var isSubagent = false

  public init() {}

  public func normalize(line data: Data) -> CodexEventBatch {
    let value: Any
    do {
      value = try JSONSerialization.jsonObject(with: data)
    } catch {
      return CodexEventBatch(
        diagnostics: [
          CodexIngestionDiagnostic(message: "Ligne JSONL invalide : \(error.localizedDescription)")
        ]
      )
    }

    guard let record = jsonObject(value) else {
      return CodexEventBatch(
        diagnostics: [CodexIngestionDiagnostic(message: "La ligne JSONL n'est pas un objet.")]
      )
    }

    let timestamp = parseCodexTimestamp(record["timestamp"])
    let recordType = jsonString(record["type"])
    guard let payload = jsonObject(record["payload"]) else { return CodexEventBatch() }

    if recordType == "session_meta" {
      return normalizeSessionMetadata(payload, timestamp: timestamp)
    }

    guard !isSubagent, let threadID else { return CodexEventBatch() }

    if recordType == "event_msg" {
      switch jsonString(payload["type"]) {
      case "task_started":
        guard let turnID = jsonString(payload["turn_id"]) else { return CodexEventBatch() }
        currentTurnID = turnID
        return CodexEventBatch(events: [
          CodexSourceEvent(
            timestamp: timestamp,
            origin: .jsonlLifecycle,
            authority: .jsonlCompleted,
            payload: .turnStarted(CodexTurnReference(threadID: threadID, turnID: turnID))
          )
        ])
      case "task_complete":
        guard let turnID = jsonString(payload["turn_id"]) ?? currentTurnID else {
          return CodexEventBatch()
        }
        if currentTurnID == turnID { currentTurnID = nil }
        return CodexEventBatch(events: [
          CodexSourceEvent(
            timestamp: timestamp,
            origin: .jsonlLifecycle,
            authority: .jsonlCompleted,
            payload: .turnCompleted(
              CodexTurnCompletion(threadID: threadID, turnID: turnID, status: "completed")
            )
          )
        ])
      case "item_completed":
        return normalizeCompletedItem(payload, threadID: threadID, timestamp: timestamp)
      default:
        return CodexEventBatch()
      }
    }

    if recordType == "response_item" {
      return normalizeResponseItem(payload, threadID: threadID, timestamp: timestamp)
    }

    return CodexEventBatch()
  }

  private func normalizeSessionMetadata(_ payload: JSONObject, timestamp: Date?) -> CodexEventBatch
  {
    guard let id = jsonString(payload["id"]) ?? jsonString(payload["session_id"]) else {
      return CodexEventBatch(
        diagnostics: [CodexIngestionDiagnostic(message: "session_meta sans identifiant de tâche.")]
      )
    }

    threadID = id
    isSubagent = Self.detectSubagent(in: payload)
    guard !isSubagent else { return CodexEventBatch() }

    return CodexEventBatch(events: [
      CodexSourceEvent(
        timestamp: timestamp,
        origin: .jsonlLifecycle,
        authority: .jsonlCompleted,
        payload: .threadObserved(
          CodexThreadMetadata(threadID: id, title: nil, isSubagent: false)
        )
      )
    ])
  }

  private func normalizeCompletedItem(
    _ payload: JSONObject,
    threadID: String,
    timestamp: Date?
  ) -> CodexEventBatch {
    guard let item = jsonObject(payload["item"]) else { return CodexEventBatch() }
    let turnID = jsonString(payload["turn_id"]) ?? currentTurnID
    guard let turnID else { return CodexEventBatch() }
    currentTurnID = turnID
    let itemID = jsonString(item["id"]) ?? fallbackItemID(item)

    switch jsonString(item["type"]) {
    case "AgentMessage", "agentMessage":
      guard let text = jsonText(from: item["content"]) ?? jsonString(item["text"]), !text.isEmpty
      else { return CodexEventBatch() }
      let message = CodexAssistantMessage(
        threadID: threadID,
        turnID: turnID,
        itemID: itemID,
        phase: CodexMessagePhase(rawValue: jsonString(item["phase"])),
        text: text
      )
      return CodexEventBatch(events: [
        CodexSourceEvent(
          timestamp: timestamp,
          origin: .jsonlCompletedItem,
          authority: .jsonlCompleted,
          payload: .assistantMessageCompleted(message)
        )
      ])
    case "UserMessage", "userMessage":
      let message = CodexUserMessageReference(
        threadID: threadID,
        turnID: turnID,
        itemID: itemID
      )
      return CodexEventBatch(events: [
        CodexSourceEvent(
          timestamp: timestamp,
          origin: .jsonlCompletedItem,
          authority: .jsonlCompleted,
          payload: .userMessageCompleted(message)
        )
      ])
    default:
      return CodexEventBatch()
    }
  }

  private func normalizeResponseItem(
    _ payload: JSONObject,
    threadID: String,
    timestamp: Date?
  ) -> CodexEventBatch {
    guard jsonString(payload["type"]) == "message",
      let turnID = currentTurnID,
      let role = jsonString(payload["role"])
    else { return CodexEventBatch() }

    let itemID = jsonString(payload["id"]) ?? fallbackItemID(payload)
    if role == "assistant" {
      guard let text = jsonText(from: payload["content"]), !text.isEmpty else {
        return CodexEventBatch()
      }
      return CodexEventBatch(events: [
        CodexSourceEvent(
          timestamp: timestamp,
          origin: .jsonlResponseItem,
          authority: .jsonlFallback,
          payload: .assistantMessageCompleted(
            CodexAssistantMessage(
              threadID: threadID,
              turnID: turnID,
              itemID: itemID,
              phase: CodexMessagePhase(rawValue: jsonString(payload["phase"])),
              text: text
            )
          )
        )
      ])
    }

    // Current Codex logs give the response_item and item_completed forms of a user
    // message different IDs. The completed form follows immediately and carries the
    // explicit turn ID, so it is the sole authoritative representation we retain.
    return CodexEventBatch()
  }

  private static func detectSubagent(in payload: JSONObject) -> Bool {
    if jsonString(payload["thread_source"])?.lowercased() == "subagent" { return true }
    return containsSubagentMarker(payload["source"])
  }

  private static func containsSubagentMarker(_ value: Any?) -> Bool {
    if let string = jsonString(value) {
      return string.lowercased().contains("subagent")
    }
    if let object = jsonObject(value) {
      return object.contains { key, value in
        key.lowercased().contains("subagent") || containsSubagentMarker(value)
      }
    }
    if let array = jsonArray(value) {
      return array.contains(where: containsSubagentMarker)
    }
    return false
  }
}
