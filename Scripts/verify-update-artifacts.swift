// Read-only release verification using only the public key, never the Keychain.
// Usage: swift Scripts/verify-update-artifacts.swift FEED DMG INFO_PLIST
import CryptoKit
import Foundation

func require(_ condition: Bool, _ message: String) throws {
  if !condition { throw NSError(domain: "ReleaseVerification", code: 1,
    userInfo: [NSLocalizedDescriptionKey: message]) }
}

do {
  try require(CommandLine.arguments.count == 4, "Expected FEED DMG INFO_PLIST")
  let feed = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
  let archive = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))
  let infoData = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[3]))
  let info = try PropertyListSerialization.propertyList(from: infoData, format: nil) as? [String: Any]
  guard let encodedKey = info?["SUPublicEDKey"] as? String,
    let keyData = Data(base64Encoded: encodedKey),
    let version = info?["CFBundleShortVersionString"] as? String,
    let build = info?["CFBundleVersion"] as? String
  else { throw NSError(domain: "ReleaseVerification", code: 2) }
  let key = try Curve25519.Signing.PublicKey(rawRepresentation: keyData)
  let marker = Data("<!-- sparkle-signatures:\n".utf8)
  guard let start = feed.range(of: marker, options: .backwards),
    let end = feed.range(of: Data("-->".utf8), in: start.upperBound..<feed.endIndex),
    let fields = String(data: feed[start.upperBound..<end.lowerBound], encoding: .utf8)
  else { throw NSError(domain: "ReleaseVerification", code: 3) }
  func field(_ name: String) -> String? {
    fields.split(separator: "\n").first { $0.hasPrefix(name + ":") }?
      .dropFirst(name.count + 1).trimmingCharacters(in: .whitespaces)
  }
  let content = Data(feed[..<start.lowerBound])
  let signature = field("edSignature").flatMap { Data(base64Encoded: $0) } ?? Data()
  try require(field("length").flatMap(Int.init) == content.count, "Incorrect feed length")
  try require(key.isValidSignature(signature, for: content), "Invalid feed signature")
  let xml = try XMLDocument(data: content, options: [])
  let items = try xml.nodes(forXPath: "//item")
  let matchingItems = try items.filter {
    try $0.nodes(forXPath: "./*[local-name()='version']").first?.stringValue == build
  }
  try require(matchingItems.count == 1, "Expected exactly one entry for this build")
  let item = matchingItems[0]
  try require(try item.nodes(forXPath: "./*[local-name()='shortVersionString']").first?.stringValue == version,
    "Incorrect release version")
  guard let enclosure = try item.nodes(forXPath: "./enclosure").first as? XMLElement else {
    throw NSError(domain: "ReleaseVerification", code: 4)
  }
  let expectedURL = "https://github.com/defrenne-lab/codex-voice/releases/download/v\(version)/Codex-Voice-3-v\(version)-macOS.dmg"
  try require(enclosure.attribute(forName: "url")?.stringValue == expectedURL, "Incorrect download URL")
  try require(enclosure.attribute(forName: "length")?.stringValue.flatMap(Int.init) == archive.count,
    "Incorrect archive length")
  let archiveSignature = enclosure.attribute(forName: "sparkle:edSignature")?.stringValue
    .flatMap { Data(base64Encoded: $0) } ?? Data()
  try require(key.isValidSignature(archiveSignature, for: archive), "Invalid archive signature")
  let digest = SHA256.hash(data: archive).map { String(format: "%02x", $0) }.joined()
  print("Verified signed feed and archive: v\(version), build \(build), \(archive.count) bytes")
  print("SHA-256: \(digest)")
} catch {
  FileHandle.standardError.write(Data("Verification failed: \(error.localizedDescription)\n".utf8))
  exit(1)
}
