# Codex Voice 3

<p align="center">
  <img src="Design/CodexVoice3-AppIcon.png" width="128" alt="Codex Voice 3 app icon combining the blue halo with a white speaker">
</p>

**Push-to-talk for Codex when the work runs on another Mac.**

Codex Voice 3 turns a headless Mac mini into the voice side of a Codex session while a MacBook remains the control surface. Codex speaks through macOS text-to-speech; pressing Option on the MacBook immediately stops the remote audio so the user can talk again.

<p align="center">
  <img src="Design/codex-voice-menu-implemented.png" width="350" alt="Codex Voice 3 menu bar controller showing an active reading, voice switch, volume and stop button">
</p>

This is an independent open-source project and is not affiliated with or endorsed by OpenAI.

## Why this exists

The first versions worked well while Codex, speech and keyboard input all lived on one Mac. That model broke down when development moved to a screenless Mac mini controlled from a MacBook or iPad:

- the push-to-talk key no longer stopped speech on the remote computer;
- volume and voice state were difficult to reach;
- parallel Codex tasks could start speaking over the task currently being discussed.

V3 is a clean Swift rewrite shaped by several months of daily use. Its product rule is deliberately simple: **the user may interrupt the voice, but one Codex task may never interrupt another.**

## Available in v0.2

- Native macOS menu-bar controller with a compact blue halo.
- Global, passive Option-key observation for immediate remote interruption.
- Voice on/off, actual Mac mini system volume and stop controls.
- Remote selection of the installed high-quality Thomas or Aurélie voice and the four proven V2 speeds.
- A pronunciation dictionary editable from the MacBook in TextEdit and synchronized to the Mac mini.
- One-click access to the configured Mac mini through macOS Screen Sharing.
- Live authenticated state over a persistent WebSocket connection.
- Localhost-only control service reached through an SSH tunnel managed by the MacBook app.
- macOS `AVSpeechSynthesizer` output on the Mac that runs Codex.
- Multi-task ingestion, deduplication and main-conversation selection.
- The menu keeps the main Codex task visible after its audio finishes.
- Click the task name to select the main conversation without sending a message.
- Previous/next paragraph replay across the five latest messages of each task.
- Gentle, grouped notifications for parallel final responses, using local excerpts.
- Non-preemptive audio queue: another Codex task cannot cut in.
- Persistent safe defaults: a new installation starts silent and re-enabling voice never replays an old backlog.
- A user LaunchAgent installer for the headless Mac; no administrator account required.
- A guided **Install and Replace** update flow when the MacBook app is opened from its DMG.
- A manual **Check for Updates** button, with signed Sparkle updates from GitHub.
- A larger speaker badge and a native translucent popover with an accessibility fallback.

The app is an Apple Silicon developer preview for macOS 13 or later. v0.2.0
introduces Developer ID signing and Apple notarization. Earlier v0.1.x archives
are not notarized; they are not replaced or republished under their old numbers.

## Architecture

Codex Voice is split into two small applications:

1. **Voice Local** runs beside Codex on the Mac mini. It follows Codex session data, decides what is eligible to speak, owns the audio queue and exposes a narrowly scoped control API on `127.0.0.1`.
2. **Voice Remote** lives in the MacBook menu bar. It reaches that API through SSH, displays the live state and turns Option into a universal “I am speaking now” command.

The controller never receives the text being read. Remote state contains only operational metadata such as voice state, system volume, task title, reading kind and queue counts. The pronunciation dictionary crosses the control channel only when the user explicitly opens or saves it. The Codex App Server is never exposed on the network.

### Conversational Mac mini control

The repository includes the `piloter-le-mac-mini` Codex skill. Once copied to `~/.codex/skills`, it lets a Codex conversation running on the Mac mini inspect audio state, change the Mac mini system volume, select one of the four proven speech speeds, enable or disable speech, and stop the current audio queue. This is especially useful when the conversation is controlled from an iPad.

```bash
cp -R skills/piloter-le-mac-mini ~/.codex/skills/
```

The skill uses the same authenticated loopback control channel as the menu bar controller. It does not expose a new network service.

## Install

### 1. Install Voice Local on the Mac mini

Xcode Command Line Tools or Xcode are required.

```shell
git clone https://github.com/defrenne-lab/codex-voice.git
cd codex-voice
Scripts/install-local-service.sh
```

The installer builds a release binary, puts it in `~/Library/Application Support/Codex Voice 3`, and registers `lab.defrenne.codexvoice3.local` as a user LaunchAgent. The service starts automatically at login and remains silent until voice is explicitly enabled.

Verify it with:

```shell
launchctl print "gui/$(id -u)/lab.defrenne.codexvoice3.local"
```

### 2. Install Voice Remote on the MacBook

Download the versioned `Codex-Voice-3-vX.Y.Z-macOS.dmg` image from the [latest release](https://github.com/defrenne-lab/codex-voice/releases/latest), then open **Codex Voice 3** from the DMG. The app offers to install itself in Applications, replace the previous version and relaunch the installed copy. Dragging it manually onto the Applications shortcut remains available as a fallback.

Copy the private control token once, replacing the placeholders with the SSH account and hostname of the Mac mini:

```shell
install -d -m 700 ~/.codex-voice
scp <mini-user>@<mini-host>:~/.codex-voice/control-token ~/.codex-voice/control-token
chmod 600 ~/.codex-voice/control-token
```

Make one normal SSH connection first so macOS records the Mac mini's host key and confirm that key-based login works without a password prompt:

```shell
ssh <mini-user>@<mini-host> true
```

Then create the private MacBook configuration used by Voice Remote:

```shell
printf '%s\n' 'CODEX_VOICE_SSH_TARGET=<mini-user>@<mini-host>' > ~/.codex-voice/.env
chmod 600 ~/.codex-voice/.env
```

Launch **Codex Voice 3**. It starts the localhost SSH tunnel, keeps it alive and reconnects automatically. No password is stored or requested by the app. If `.env` is absent, the previous manually managed tunnel remains supported.

On first use, macOS may request Input Monitoring permission. The app observes Option without consuming or modifying the event, so Codex still receives its normal push-to-talk shortcut.

Moving from v0.1.x to v0.2.0 requires one manual installation to bootstrap the
updater. Always verify that the archive came from this repository and compare
its published SHA-256 checksum. Developer ID signing and notarization do not
grant Input Monitoring permission; macOS may ask you to authorize Option again.

## Using it

- Left-click the halo to open controls.
- Click anywhere outside the popover to dismiss it.
- Press Option while audio is playing to abandon the current reading and its queued fragments.
- Click the main task name to select a conversation; use the small arrows to replay a paragraph.
- Parallel notifications wait ten seconds after foreground speech. One interruption cancels the whole batch, including its remaining entries.
- Switch **Voix active** off before leaving long-running overnight tasks.
- Adjust the actual Mac mini output volume with the volume slider.
- Open **Dictionnaire** to edit pronunciations in TextEdit. Saving synchronizes the live file to the Mac mini.
- Click **Ouvrir le partage d’écran** to reach the configured Mac mini directly, including while Codex Voice is offline.
- Right-click the halo to quit the MacBook controller.
- Choose **Rechercher une mise à jour…** to check GitHub and explicitly install an available controller update.

An interruption is not a pause: speech never resumes automatically. The full answer remains visible in Codex.

## Build and test

```shell
swift test
Scripts/build-remote-app.sh
Scripts/package-remote-app.sh
```

Local builds remain ad-hoc signed by default. A release maintainer can select a persistent identity without committing it:

```shell
CODEX_VOICE_SIGNING_IDENTITY="<certificate name or SHA-1>" Scripts/package-remote-app.sh
```

For repeatable releases, that value may instead be stored as the only line of the gitignored `.signing-identity.local` file on the build Mac. The file contains an identity reference, not the private key; the key remains protected by the macOS Keychain.

The package script creates a versioned disk image such as `.build/Codex-Voice-3-v0.2.0-macOS.dmg` and a matching SHA-256 file. The DMG contains the signed application, which offers guided installation, plus an Applications shortcut as a manual fallback. Automated tests cover ingestion, task-title updates, ordering, orchestration, audio coordination, authentication, remote settings, pronunciation handling, SSH configuration, installation, manual-update policy, deduplication and token permissions.

For notarized releases, an explicit `CODEX_VOICE_DISTRIBUTION=1` mode
requires a Developer ID Application identity and adds Hardened Runtime, secure
timestamps and DMG signing. See [DISTRIBUTION.md](DISTRIBUTION.md) for private
Keychain setup, notarization, final checksum generation and release checks. This
preparation never changes an already published release.

The app integrates **Rechercher une mise à jour…** using
Sparkle 2.9.6. Checks and installations are manual, and update archives and the
GitHub-hosted feed must be signed. This updates only the menu app, not the
Mac mini service. The first updater-enabled release still needs a bootstrap
installation. An isolated replacement/relaunch test passed. See
[UPDATES.md](UPDATES.md) for publication order and bootstrap validation.

### Multi-task reading in v0.2

The app adds manual main-task selection, previous/next paragraph
replay, up to five recent assistant messages per task, and grouped short
notifications for parallel final responses. Notifications wait ten seconds
after foreground speech and two seconds between entries; one interruption
discards the whole notification batch. The current summary is a bounded local
excerpt, not an AI rewrite, and sends no text to an external provider.

The transcript reader consumes bounded chunks in a single forward scan and
only bootstraps a bounded tail when an old journal returns. Historical context
never selects a task or starts speech. Code and table blocks are represented
by short spoken placeholders. The menu adds a larger speaker badge and a native
translucent backdrop, with an opaque accessibility fallback.

This batch requires both the Mac mini service and MacBook controller to be
updated; Sparkle only updates the controller. Older peers retain existing
controls but cannot expose the new selector/history commands. See
[BATCH-VALIDATION.md](BATCH-VALIDATION.md) before deploying.

## Pronunciation dictionary and GitHub

The live dictionary belongs to the Mac mini runtime and remains mutable across application updates:

```text
~/Library/Application Support/Codex Voice 3/pronunciations.csv
```

[`Dictionary/pronunciations.fr-FR.csv`](Dictionary/pronunciations.fr-FR.csv) is a separate public snapshot: it provides a useful default for a fresh installation and a durable, versioned reference. The app deliberately does not commit to GitHub. When the live dictionary is worth preserving, refresh the repository copy explicitly, review it for private data, then commit it:

```shell
Scripts/snapshot-pronunciation-dictionary.sh
git diff -- Dictionary/pronunciations.fr-FR.csv
```

This keeps GitHub useful as a lightweight reference store without making source control part of the runtime or requiring a GitHub credential inside the app.

## Security model

- The control server binds only to `127.0.0.1`.
- Plain WebSockets are accepted only for localhost; non-local endpoints must use TLS.
- A random 256-bit bearer token is created locally with `0700` directory and `0600` file permissions.
- The token, transcripts and diagnostic state are never part of the release archive.
- The public reference dictionary is reviewed and committed explicitly; the mutable runtime file is not uploaded automatically.
- The SSH target is read from the MacBook's private `~/.codex-voice/.env`, validated before it becomes a process argument, and never included in the release.
- The managed SSH process accepts key-based authentication only and forwards loopback port `48731` to the same loopback port on the Mac mini.
- Releases v0.1.5–v0.1.9 use a persistent development identity; v0.2.0 switches to Developer ID. This is separate from macOS privacy permissions and does not guarantee that Input Monitoring will never need reauthorization.
- The remote API controls voice only; it does not expose arbitrary Codex operations.

See [SECURITY.md](SECURITY.md) and [REMOTE-CONTROL.md](REMOTE-CONTROL.md) for the protocol and threat boundaries.

## Next

The foundations intentionally come before the richer experience. Planned work includes:

- richer summaries if local extraction proves insufficient in daily use;
- further spoken-text adaptation for long technical paragraphs;
- direct device pairing for a future iPad surface;
- a lightweight iPad control surface.

The design rationale lives in [PRODUCT-BRIEF-V3.md](PRODUCT-BRIEF-V3.md). Architecture probes and validated trade-offs are kept in the repository so the project remains understandable rather than becoming a black box.

## License

[MIT](LICENSE) © 2026 Sébastien Defrenne.
