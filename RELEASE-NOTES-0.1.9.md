# Codex Voice 3 v0.1.9

Reliable push-to-talk follow-ups and a clearer Mac installation experience.

## Fixed

- Pressing Option still abandons the complete reading and its queued fragments, but a new user message now starts a fresh audio interaction even when Codex keeps the same internal turn identifier.
- Follow-up answers no longer remain silent after the user interrupts a response to speak again.

## Added

- A recognizable application icon combining the V3 blue halo with the white V2-style speaker.
- The menu-bar halo now contains the same speaker, with distinct active, silent and disconnected states.
- When launched from a DMG, Codex Voice 3 now offers **Installer et remplacer**, copies itself into Applications, replaces the previous version and relaunches the installed copy.
- Manual drag-and-drop installation remains available as a fallback.

Both the Mac mini service and the MacBook controller must be updated for the audio-interaction fix. The guided installer is part of the MacBook application.
