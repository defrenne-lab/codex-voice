// swift-tools-version: 5.9

import PackageDescription

let package = Package(
  name: "CodexVoice3",
  platforms: [
    .macOS(.v13)
  ],
  products: [
    .library(name: "CodexVoiceCore", targets: ["CodexVoiceCore"]),
    .library(name: "CodexVoiceMacOS", targets: ["CodexVoiceMacOS"]),
    .executable(name: "codex-voice-probe", targets: ["CodexVoiceProbe"]),
    .executable(name: "codex-voice-ingest", targets: ["CodexVoiceIngest"]),
    .executable(name: "codex-voice-local", targets: ["CodexVoiceLocal"]),
    .executable(name: "codex-voice-remote", targets: ["CodexVoiceRemote"]),
    .executable(name: "codex-voice-menu", targets: ["CodexVoiceMenu"]),
  ],
  dependencies: [
    .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.6"),
  ],
  targets: [
    .target(
      name: "CodexVoiceCore",
      path: "Sources/CodexVoiceCore"
    ),
    .executableTarget(
      name: "CodexVoiceProbe",
      path: "Sources/CodexVoiceProbe"
    ),
    .target(
      name: "CodexVoiceMacOS",
      dependencies: ["CodexVoiceCore"],
      path: "Sources/CodexVoiceMacOS"
    ),
    .executableTarget(
      name: "CodexVoiceIngest",
      dependencies: ["CodexVoiceCore"],
      path: "Sources/CodexVoiceIngest"
    ),
    .executableTarget(
      name: "CodexVoiceLocal",
      dependencies: ["CodexVoiceCore", "CodexVoiceMacOS"],
      path: "Sources/CodexVoiceLocal"
    ),
    .executableTarget(
      name: "CodexVoiceRemote",
      dependencies: ["CodexVoiceCore", "CodexVoiceMacOS"],
      path: "Sources/CodexVoiceRemote"
    ),
    .executableTarget(
      name: "CodexVoiceMenu",
      dependencies: [
        "CodexVoiceCore",
        "CodexVoiceMacOS",
        .product(name: "Sparkle", package: "Sparkle"),
      ],
      path: "Sources/CodexVoiceMenu",
      linkerSettings: [
        .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
      ]
    ),
    .testTarget(
      name: "CodexVoiceProbeTests",
      dependencies: ["CodexVoiceProbe"],
      path: "Tests/CodexVoiceProbeTests"
    ),
    .testTarget(
      name: "CodexVoiceCoreTests",
      dependencies: ["CodexVoiceCore"],
      path: "Tests/CodexVoiceCoreTests"
    ),
    .testTarget(
      name: "CodexVoiceMacOSTests",
      dependencies: ["CodexVoiceMacOS"],
      path: "Tests/CodexVoiceMacOSTests"
    ),
    .testTarget(
      name: "CodexVoiceMenuTests",
      dependencies: ["CodexVoiceMenu"],
      path: "Tests/CodexVoiceMenuTests"
    ),
  ]
)
