import Foundation

public struct AppServerSnapshotEventSource {
  public init() {}

  public func normalize(threadReadData data: Data) -> CodexEventBatch {
    let value: Any
    do {
      value = try JSONSerialization.jsonObject(with: data)
    } catch {
      return CodexEventBatch(
        diagnostics: [
          CodexIngestionDiagnostic(
            message: "Instantané App Server invalide : \(error.localizedDescription)")
        ]
      )
    }

    guard let root = jsonObject(value) else {
      return CodexEventBatch(
        diagnostics: [CodexIngestionDiagnostic(message: "Instantané App Server sans tâche.")]
      )
    }

    let thread: JSONObject?
    if jsonString(root["id"]) != nil {
      thread = root
    } else if let direct = jsonObject(root["thread"]) {
      thread = direct
    } else {
      thread = jsonObject(root["result"]).flatMap { jsonObject($0["thread"]) }
    }
    guard let thread else {
      return CodexEventBatch(
        diagnostics: [CodexIngestionDiagnostic(message: "Instantané App Server sans tâche.")]
      )
    }
    return normalize(thread: thread)
  }

  private func normalize(thread: JSONObject) -> CodexEventBatch {
    guard let threadID = jsonString(thread["id"]) else {
      return CodexEventBatch(
        diagnostics: [
          CodexIngestionDiagnostic(message: "Instantané App Server sans identifiant de tâche.")
        ]
      )
    }

    var events: [CodexSourceEvent] = [
      CodexSourceEvent(
        timestamp: nil,
        origin: .appServerSnapshot,
        authority: .appServerSnapshot,
        payload: .threadObserved(
          CodexThreadMetadata(
            threadID: threadID,
            title: jsonString(thread["name"]),
            isSubagent: false
          )
        )
      )
    ]

    for turnValue in jsonArray(thread["turns"]) ?? [] {
      guard let turn = jsonObject(turnValue), let turnID = jsonString(turn["id"]) else { continue }
      events.append(
        CodexSourceEvent(
          timestamp: nil,
          origin: .appServerSnapshot,
          authority: .appServerSnapshot,
          payload: .turnStarted(CodexTurnReference(threadID: threadID, turnID: turnID))
        )
      )

      for itemValue in jsonArray(turn["items"]) ?? [] {
        guard let item = jsonObject(itemValue) else { continue }
        let itemID = jsonString(item["id"]) ?? fallbackItemID(item)
        switch jsonString(item["type"]) {
        case "agentMessage", "AgentMessage":
          guard let text = jsonString(item["text"]) ?? jsonText(from: item["content"]),
            !text.isEmpty
          else { continue }
          events.append(
            CodexSourceEvent(
              timestamp: nil,
              origin: .appServerSnapshot,
              authority: .appServerSnapshot,
              payload: .assistantMessageCompleted(
                CodexAssistantMessage(
                  threadID: threadID,
                  turnID: turnID,
                  itemID: itemID,
                  phase: CodexMessagePhase(rawValue: jsonString(item["phase"])),
                  text: text
                )
              )
            )
          )
        case "userMessage", "UserMessage":
          events.append(
            CodexSourceEvent(
              timestamp: nil,
              origin: .appServerSnapshot,
              authority: .appServerSnapshot,
              payload: .userMessageCompleted(
                CodexUserMessageReference(threadID: threadID, turnID: turnID, itemID: itemID)
              )
            )
          )
        default:
          continue
        }
      }

      let status = statusString(turn["status"]) ?? "unknown"
      if status != "inProgress" && status != "in_progress" && status != "active" {
        events.append(
          CodexSourceEvent(
            timestamp: nil,
            origin: .appServerSnapshot,
            authority: .appServerSnapshot,
            payload: .turnCompleted(
              CodexTurnCompletion(threadID: threadID, turnID: turnID, status: status)
            )
          )
        )
      }
    }

    return CodexEventBatch(events: events)
  }
}
