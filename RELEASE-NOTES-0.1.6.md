# Codex Voice 3 v0.1.6

Persistent main-task context and more natural menu behavior.

## Added

- When speech finishes, the menu now keeps showing the main Codex task beneath **En attente**.
- Task names are refreshed from Codex's lightweight local session index, including later renames, without querying or exposing the App Server.

## Improved

- Clicking outside the menu popover now closes it while preserving Codex keyboard focus.
- The remote protocol carries main-task metadata without carrying message text.

Both the Mac mini service and the MacBook controller must be updated for the main-task display. The recommended download is the versioned `Codex-Voice-3-v0.1.6-macOS.dmg`; open it and drag the application onto its Applications shortcut. The original ZIP remains available as a fallback for this release.
