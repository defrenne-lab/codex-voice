# Codex Voice 3 v0.1.7

System-volume control and a remotely editable pronunciation dictionary.

## Added

- **Dictionnaire** opens the live pronunciation list in TextEdit on the MacBook.
- Saving the file synchronizes it to the Mac mini through the existing authenticated SSH/WebSocket channel.
- Existing V2 dictionaries are migrated on first install; the repository also contains a public reference snapshot.

## Fixed

- The menu volume slider now changes the actual Mac mini output volume instead of an application-only speech gain.
- Speech always uses full application gain, leaving one clear and predictable volume control.

Both the Mac mini service and the MacBook controller must be updated. Install the local service from this version first, then install the versioned `Codex-Voice-3-v0.1.7-macOS.dmg` on the MacBook.
