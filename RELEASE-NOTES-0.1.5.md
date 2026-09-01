# Codex Voice 3 v0.1.5

Visible versions and a stable macOS application identity.

## Added

- The popover now displays the installed version beside the Codex Voice 3 name.

## Improved

- The release archive uses a persistent Apple Development signature instead of a version-specific ad-hoc identity.
- Successive updates can now satisfy the same macOS designated requirement, so Input Monitoring authorization should survive future replacements of the app.
- The build script accepts `CODEX_VOICE_SIGNING_IDENTITY` or the gitignored maintainer file `.signing-identity.local`, while keeping ordinary contributor builds ad-hoc signed by default.

Because v0.1.5 changes from the previous ad-hoc identity, macOS may request Input Monitoring permission one final time during this update. The app is still an unnotarized developer preview; Developer ID signing remains the future public-distribution target.

The Mac mini service is unchanged from v0.1.3. The automatic SSH tunnel introduced in v0.1.4 and this release's interface and signing changes require only a MacBook controller update.
