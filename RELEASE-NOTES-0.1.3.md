# Codex Voice 3 v0.1.3

High-quality macOS voice selection.

## Improved

- Thomas Premium, reported as Thomas Enhanced by the macOS speech API, is now preferred over Thomas Compact.
- Aurélie Enhanced keeps the same high-quality selection behavior.
- Compact voices are no longer presented as recommended Thomas or Aurélie voices.
- The new `piloter-le-mac-mini` Codex skill controls system volume, voice volume, the four V2 speech speeds, voice activation and immediate interruption from a conversation.
- The local installer now deploys the authenticated command-line controller used by the skill.

The Mac mini service must be reinstalled to deploy the skill controller and refresh its installed voice catalog. The MacBook controller must be updated to v0.1.3.
