import Foundation

struct ApplicationUpdateConfiguration {
  let bundleURL: URL
  let feedURL: URL?
  let publicKey: String?
  let isPreview: Bool
  let isReadOnlyVolume: Bool

  static func current(bundle: Bundle = .main, isPreview: Bool = false) -> Self {
    let resources = try? bundle.bundleURL.resourceValues(forKeys: [.volumeIsReadOnlyKey])
    return Self(
      bundleURL: bundle.bundleURL,
      feedURL: (bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String)
        .flatMap(URL.init(string:)),
      publicKey: bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
      isPreview: isPreview,
      isReadOnlyVolume: resources?.volumeIsReadOnly ?? false
    )
  }

  var unavailabilityReason: String? {
    if isPreview { return "Indisponible dans l’aperçu." }
    guard bundleURL.pathExtension == "app" else {
      return "Ouvre la version installée de Codex Voice 3."
    }
    let components = bundleURL.standardizedFileURL.pathComponents
    if isReadOnlyVolume || components.contains("AppTranslocation")
      || components.starts(with: ["/", "Volumes"])
    {
      return "Installe l’app dans Applications, puis ouvre cette copie."
    }
    guard let feedURL, feedURL.scheme?.lowercased() == "https",
      let host = feedURL.host, !host.isEmpty,
      feedURL.user == nil, feedURL.password == nil
    else {
      return "Le flux de mise à jour sécurisé n’est pas configuré."
    }
    guard let publicKey, Data(base64Encoded: publicKey)?.count == 32 else {
      return "La clé de vérification des mises à jour n’est pas configurée."
    }
    return nil
  }
}
