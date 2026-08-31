import Foundation

typealias JSONObject = [String: Any]

func jsonObject(_ value: Any?) -> JSONObject? {
  value as? JSONObject
}

func jsonArray(_ value: Any?) -> [Any]? {
  value as? [Any]
}

func jsonString(_ value: Any?) -> String? {
  guard !(value is NSNull) else { return nil }
  return value as? String
}

func jsonText(from value: Any?) -> String? {
  if let direct = jsonString(value), !direct.isEmpty { return direct }
  guard let parts = jsonArray(value) else { return nil }
  let texts = parts.compactMap { part -> String? in
    guard let object = jsonObject(part) else { return nil }
    return jsonString(object["text"])
  }
  guard !texts.isEmpty else { return nil }
  return texts.joined(separator: "\n")
}

func parseCodexTimestamp(_ value: Any?) -> Date? {
  guard let raw = jsonString(value) else { return nil }
  if let date = ISO8601DateFormatter.codexFractional.date(from: raw) { return date }
  return ISO8601DateFormatter.codexBasic.date(from: raw)
}

extension ISO8601DateFormatter {
  fileprivate static let codexFractional: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }()

  fileprivate static let codexBasic = ISO8601DateFormatter()
}

func fallbackItemID(_ object: JSONObject) -> String {
  guard JSONSerialization.isValidJSONObject(object),
    let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
  else {
    return "fallback-\(String(describing: object).hashValue)"
  }

  var hash: UInt64 = 14_695_981_039_346_656_037
  for byte in data {
    hash ^= UInt64(byte)
    hash &*= 1_099_511_628_211
  }
  return String(format: "fallback-%016llx", hash)
}

func statusString(_ value: Any?) -> String? {
  if let value = jsonString(value) { return value }
  if let object = jsonObject(value) { return jsonString(object["type"]) }
  return nil
}
