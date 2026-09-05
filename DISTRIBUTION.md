# Developer ID distribution

This procedure prepares the MacBook menu app for direct distribution outside
the Mac App Store. It does not install the app, update the Mac mini service,
or publish a GitHub release. The separate [updater guide](UPDATES.md) covers
Sparkle keys, the signed feed and update testing.

v0.2.0 is the first Developer ID signed and notarized release. The earlier
v0.1.9 release remains **not notarized** and is not replaced. Never replace an
existing release asset with a differently signed build bearing the same version.

## Signing identity — once per build Mac

Import a **Developer ID Application** certificate and its matching private key
into the build account's Keychain. No changes to other apps' certificates,
provisioning profiles or signing settings are required.

Keep an encrypted `.p12` backup somewhere private, preferably also off the build
Mac. Never commit it, its password, an API key, or an Apple account password.

Inspect usable identities (this does not reveal private keys):

```shell
security find-identity -v -p codesigning
```

Store the selected certificate's SHA-1 as the only line of the gitignored
`.developer-id.local` file. Alternatively, pass its exact name or SHA-1 using
`CODEX_VOICE_SIGNING_IDENTITY`. This is only a public identity reference; the
private key stays in the Keychain. Development builds continue to use the
separate `.signing-identity.local` configuration.

## Notarization credentials — once per build Mac

Create a new [Apple app-specific password](https://support.apple.com/102654),
labelled for this workflow, without changing or revoking any existing password.
The label is an organizational aid, not an app-level authorization boundary.

In an interactive Terminal **on the build Mac**, run:

```shell
xcrun notarytool store-credentials "codex-voice-3-notary" \
  --apple-id "<Apple account email>" \
  --team-id "<Developer team ID>"
```

Paste the app-specific password at the secure password prompt. Do not include a
`--password` argument, put it in an environment file, or send it in a chat. The
tool validates the credentials before saving them to the Keychain. This profile
name is reserved for Codex Voice; do not reuse another project's profile.

## Prepare a candidate

Before a real release, update both version fields in
`Resources/CodexVoiceRemote-Info.plist` and run the tests:

```shell
swift test
CODEX_VOICE_DISTRIBUTION=1 Scripts/package-remote-app.sh
```

Distribution mode requires an exact, valid Developer ID Application identity.
It refuses ad-hoc, local and Apple Development signatures. The app is signed
with Hardened Runtime and a secure timestamp. Sparkle and its nested helpers
are embedded and signed inside-out with the same identity. The DMG is also
signed and signatures are verified recursively. An internet connection to Apple's timestamp service is
required. The first signing operation may request permission to use the private
key in the Keychain; do not change global key-access rules to bypass it.

All output destinations must remain inside this project's disposable `.build`
directory. Packaging does **not** notarize or publish anything. At this point the
DMG and checksum are only a candidate, not a ready-to-publish release.

## Submit, verify, staple

Replace the sample version below with the candidate's real version. Submit only
the DMG, not the source tree or signing credentials:

```shell
xcrun notarytool submit ".build/Codex-Voice-3-vX.Y.Z-macOS.dmg" \
  --keychain-profile "codex-voice-3-notary" --wait
```

Keep the returned submission ID. Proceed only when the status is **Accepted**.
If the connection is interrupted, query that submission with `notarytool info`
or `notarytool wait` rather than submitting another copy:

```shell
xcrun notarytool info "<submission-id>" \
  --keychain-profile "codex-voice-3-notary"
xcrun notarytool wait "<submission-id>" \
  --keychain-profile "codex-voice-3-notary" --timeout 5m
```

`In Progress` is not an acceptance or a rejection. A local wait timeout does not
cancel Apple's analysis. Keep the original DMG unchanged and retain its
submission ID and pre-stapling SHA-256 so verification can resume later. Apple
notes that additional analysis can take significantly longer than the usual
processing time; see [Apple Developer Support's explanation](https://developer.apple.com/forums/thread/822109).
Do not replace signing credentials, repeatedly resubmit, or disable security
checks just because the request is still processing.

Once the status is **Accepted**, download and inspect the log, including any
warnings, before stapling:

```shell
xcrun notarytool log "<submission-id>" \
  --keychain-profile "codex-voice-3-notary" \
  ".build/notary-log.json"
xcrun stapler staple ".build/Codex-Voice-3-vX.Y.Z-macOS.dmg"
xcrun stapler validate ".build/Codex-Voice-3-vX.Y.Z-macOS.dmg"
codesign --verify --strict --verbose=2 ".build/Codex-Voice-3-vX.Y.Z-macOS.dmg"
spctl --assess --type open --context context:primary-signature --verbose=2 \
  ".build/Codex-Voice-3-vX.Y.Z-macOS.dmg"
```

**Stapling changes the DMG bytes.** After all checks succeed, regenerate its
checksum; never publish the pre-notarization checksum:

```shell
(cd .build && shasum -a 256 "Codex-Voice-3-vX.Y.Z-macOS.dmg" \
  > "Codex-Voice-3-vX.Y.Z-macOS.dmg.sha256")
```

Do not rebuild, re-sign or repackage this accepted artifact before publishing.
Test the actual downloaded DMG and installed app on a second Mac, including
launch, SSH, Option interruption, and permissions. Notarization does not grant
Input Monitoring permission; the transition from Apple Development to
Developer ID may still require the user to authorize the app once again.

## CI and future updates

The existing CI remains a credential-free build and test workflow. Signing and
notarization run explicitly on the configured build Mac. No certificate export,
Apple password or Keychain modification is added to CI.

The source now includes a manual **Check for Updates** button using Sparkle.
Follow [UPDATES.md](UPDATES.md) for signed-feed publication and verification.
The isolated replacement/relaunch test passed. A real MacBook bootstrap is
still required when moving from v0.1.x; Developer ID and notarization alone do
not validate SSH, Option permissions or subjective audio behavior on that Mac.

## Apple references

- [Notarization requirements](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- [Custom command-line notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)
- [Packaging, stapling and distribution testing](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution)
