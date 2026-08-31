# Codex Voice 3 v0.1.2

Focus-safe push-to-talk on the MacBook.

## Fixed

- The controller popover no longer explicitly makes itself the key window.
- Pressing Option closes the popover before push-to-talk continues.
- When necessary, pressing Option restores the application that was active before the popover opened.

This prevents Return from being sent to the controller popover with a macOS alert sound instead of submitting the current prompt in Codex.

The Mac mini service is unchanged from v0.1.1. This is a MacBook controller update only.
