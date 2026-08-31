import CryptoKit
import Foundation

typealias JSONObject = [String: Any]

func object(_ value: Any?) -> JSONObject? {
  value as? JSONObject
}

func array(_ value: Any?) -> [Any]? {
  value as? [Any]
}

func string(_ value: Any?) -> String? {
  if value is NSNull { return nil }
  return value as? String
}

func integer(_ value: Any?) -> Int? {
  if let number = value as? NSNumber {
    return number.intValue
  }
  return value as? Int
}

func bool(_ value: Any?) -> Bool? {
  if let number = value as? NSNumber {
    return number.boolValue
  }
  return value as? Bool
}

func canonicalDigest(_ value: Any) -> String {
  guard JSONSerialization.isValidJSONObject(value),
    let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
  else {
    return String(describing: value)
  }

  return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

func clipped(_ text: String, limit: Int = 120) -> String {
  let normalized =
    text
    .replacingOccurrences(of: "\n", with: " ")
    .replacingOccurrences(of: "\r", with: " ")
    .split(whereSeparator: { $0.isWhitespace })
    .joined(separator: " ")

  guard normalized.count > limit else { return normalized }
  return String(normalized.prefix(limit)) + "…"
}

func shortID(_ id: String?) -> String {
  guard let id, !id.isEmpty else { return "—" }
  return String(id.prefix(12))
}

func isoTimestamp() -> String {
  ISO8601DateFormatter().string(from: Date())
}

func writeJSON(_ value: Any, to url: URL) throws {
  let directory = url.deletingLastPathComponent()
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  let data = try JSONSerialization.data(
    withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
  try data.write(to: url, options: .atomic)
}
