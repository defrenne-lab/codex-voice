# Codex Voice 3 v0.1.1

Audio reliability and remote speech settings.

## Changed

- Runs Voice Local with interactive scheduling after Core Audio diagnostics identified skipped playback cycles under background throttling.
- Adds compact remote voice selection for the installed Thomas and Aurélie voices.
- Adds the four speed presets proven in Codex Voice 2: Slow 0.38, Normal 0.48, Fast 0.53 and Very Fast 0.58.
- Publishes the installed French voice catalog through the authenticated, text-free control state.
- Makes LaunchAgent upgrades resilient to asynchronous `launchctl` removal.

## Requirements

- macOS 13 or later.
- Apple Silicon for the attached prebuilt app.
- Voice Local from the current `main` branch or this release installed on the Mac that runs Codex.

The archive is ad-hoc signed and not notarized. Verify the attached SHA-256 checksum before first launch.
