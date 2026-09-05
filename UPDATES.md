# Manual in-app updates

## Scope and current status

The menu app uses [Sparkle 2.9.6](https://github.com/sparkle-project/Sparkle/releases/tag/2.9.6),
locked by `Package.swift` and `Package.resolved`. The popover and right-click
menu provide **Rechercher une mise à jour** (without the ellipsis starting in
v0.2.1). This action is independent of the
Mac mini connection and closes the popover before showing Sparkle's own UI.

There are no scheduled update checks, automatic installations or system-profile
submissions. Starting the updater does not itself request a check. Opening an
app from a mounted volume, a read-only/translocated location, or preview mode
disables this command with an explanation. Sparkle handles download progress,
verification, replacement and relaunch, after the user's confirmation.

Only **Voice Remote**, the menu app on the MacBook, is updated. The Mac mini
service, SSH configuration, dictionary, control token and voice settings are
not migrated or modified by this updater.

**v0.2.0 / build 11 is the first updater-enabled release.** The production feed
advertises the signed and notarized v0.2.1 and v0.2.0 releases, not disposable test builds
or earlier non-notarized versions. The isolated end-to-end test validated the
update UI, rejection paths, actual replacement and self-relaunch. The first
manual installation on the MacBook was confirmed by the user on 2026-09-05,
along with the manual no-update check. v0.2.1 is the first follow-up release
intended to test the production replacement/relaunch on that MacBook;
see [RELEASE-VALIDATION-0.2.1.md](RELEASE-VALIDATION-0.2.1.md).
See [BATCH-VALIDATION.md](BATCH-VALIDATION.md) for the combined release checks.

Local validation on 2026-09-05: 80 automated tests pass, including independent
public-key verification of the initial feed and rejection of altered content.
Ad-hoc and Developer ID test bundles both pass recursive signature validation;
the Developer ID app and embedded Sparkle use the same team, Hardened Runtime
and secure timestamps. The feed is signed and also verified by Sparkle's tool.
Two disposable updater-enabled test versions have since been notarized and
stapled successfully. No updater-enabled production release has been published
or installed in `/Applications` at that stage of the isolated testing.

### Isolated end-to-end test — 2026-09-05

The fixture uses a separate bundle ID and preferences domain, no SSH or control
token, no key monitor, a disconnected voice configuration and a loopback feed.
Only the fixture permits loopback HTTP; production still requires HTTPS. A
persistent test window makes lifecycle observation possible while exercising
the actual update controller and popover action.

Verified through the real Sparkle UI:

- No automatic feed request on launch; manual checks work without Voice Local.
- An empty signed feed reports the installed version as current.
- An altered feed is rejected; an unavailable feed reports a download error.
- The offered source/target versions are correct; dismissing the offer leaves
  the original build unchanged.
- A corrupted download is rejected before installation.
- The valid, signed and notarized DMG downloads and passes signature checks.
- Re-entering the update action focuses the existing installation window
  rather than starting another download.
- After the user accepted the test's Documents-folder access request, Sparkle
  replaced build 900001 with 900002 and relaunched the app at the same path.
- The running app shows 0.0.2-test; the new executable and Info.plist match the
  intended target byte-for-byte, and its new payload resource is present.
- Recursive strict code-signature verification succeeds; Gatekeeper accepts
  the installed result as Notarized Developer ID.
- The separate test-domain preferences sentinel survives unchanged.
- A subsequent manual check reports 0.0.2-test as current, with only one feed
  request and no archive download. The test app and local server were stopped.

**Resolved test-environment wait:** the atomic bundle swap (`renamex_np`)
waited for macOS Documents-folder permission because this fixture lived inside
the repository under Documents. The user confirmed and accepted that prompt;
replacement and self-relaunch then completed without an installer restart or
code change. This does not establish which prompts a first installation or an
update in `/Applications` will show on another Mac.

The test automation must not inspect/reopen the target app immediately after
requesting its termination: the UI tool can automatically launch a closed app.
One old-version relaunch occurred this way; it was closed again. Observe the
installer instead and use read-only build/PID checks before attaching to the
restarted app. An earlier ad-hoc test copy was also found running and closed;
claims that no test app had launched before the unlocked session were incorrect.

The fixture does not exercise real MacBook SSH/Option behavior or preservation
of actual user settings: these and the bootstrap installation remain release
gates. No privacy permission was reset or widened by the test scripts; the
user explicitly approved the test fixture's Documents access in macOS.

## Three independent checks

- Apple Developer ID signs the app, all embedded Sparkle helpers and the DMG.
- Apple notarization validates each complete release artifact; staple and
  verify the result as described in [DISTRIBUTION.md](DISTRIBUTION.md).
- Sparkle's Ed25519 key signs the final DMG bytes and the XML update feed.
  Verification before extraction is required. A bad feed signature never
  falls back to an unsigned feed, even after repeated failures.

The public verification key is in `Resources/CodexVoiceRemote-Info.plist` and
may be public. Its **private** counterpart is a dedicated login-Keychain item
with account `lab.defrenne.codexvoice3.remote`; it is not the Apple certificate
and is not included in the app, Git, CI, `.env`, logs or release artifacts.
Never recreate this key on every release or change the published public key
without planning Sparkle's key-rotation procedure. Arrange a secure private
backup before the first release; no private-key export is automated here.

The tools below are supplied by the pinned dependency after `swift package resolve`:

```shell
.build/artifacts/sparkle/Sparkle/bin/generate_keys --account lab.defrenne.codexvoice3.remote -p
```

This prints only the existing public key. Compare it with `SUPublicEDKey`.
Grant a Keychain prompt only to the expected signing tool; do not put a password
on the command line or change global access rules to suppress prompts.

## Prepare a future release feed

1. Increase **both** version fields. `CFBundleVersion` must be strictly greater
   than every released build: Sparkle uses it to order updates.
2. Build, sign, notarize, staple and verify the final versioned DMG. Do not
   modify it afterwards. Update its checksum after stapling.
3. Create a fresh staging directory under `.build` containing a **copy** of that
   final DMG and the existing signed `Updates/appcast.xml`. Never run the
   generator on `.build` as a whole: it could discover test archives.
4. Optionally add reviewed release notes with the same base filename as the
   DMG and a `.txt` extension. No private conversation content belongs here.
5. Generate the candidate feed with the official tool, substituting the real
   version and the exact staging directory:

```shell
.build/artifacts/sparkle/Sparkle/bin/generate_appcast \
  --account lab.defrenne.codexvoice3.remote \
  --download-url-prefix https://github.com/defrenne-lab/codex-voice/releases/download/vX.Y.Z/ \
  --maximum-deltas 0 --maximum-versions 0 --embed-release-notes \
  .build/update-feed-STAGING

swift Scripts/verify-update-artifacts.swift \
  .build/update-feed-STAGING/appcast.xml \
  .build/update-feed-STAGING/Codex-Voice-3-vX.Y.Z-macOS.dmg \
  Resources/CodexVoiceRemote-Info.plist
```

Existing entries retain their version-specific download URLs. The generator
signs the archive and feed using the app's `SURequireSignedFeed` setting.
The verifier uses only the embedded public key, without requesting private-key
access. It checks both signatures, lengths, release/build and download URL.
Review version/build, minimum macOS, architecture, asset URL, size, release
notes and signatures. No delta updates or pruning are needed for now.

Publish only after explicit approval: first the GitHub release and its final
DMG/checksum, then the generated `Updates/appcast.xml` on `main`. Verify the
actual downloaded artifact and public feed before announcing the release.
The stable feed URL is:

`https://raw.githubusercontent.com/defrenne-lab/codex-voice/main/Updates/appcast.xml`

The XML signature is embedded in the file. Copy its bytes unchanged; do not
reformat, edit release text or insert a newline afterwards. A modification
requires re-signing. An empty initial feed can be signed with `sign_update`
using the same account and verified with `--verify`.

## Release checks and regression checklist

The isolated test above is complete. Repeat it when changing the updater or
packaging, using disposable signed copies and a separate test feed. Do not
point the public catalog at test releases or replace the user's working app:

- Check the visible versions of the source and target builds.
- Confirm no update request is sent on launch or without clicking the button.
- Check while the Mac mini is disconnected; voice operation must not be needed.
- Exercise no-update, network error, cancellation and repeated-click cases.
- Verify a valid feed/archive succeeds and altered feed/archive bytes fail.
- Accept an update and confirm the actual bundle is replaced and relaunched;
  inspect its new build number and signature, not just a success dialog.
- Confirm settings and SSH access survive; then verify Option on the MacBook.
- Test the first bootstrap install from the actual released DMG on a second Mac.

On each release, verify the actual public HTTPS feed and downloaded artifact.
For the first updater-enabled release, also perform the normal bootstrap install
on the MacBook and verify SSH/Option/settings behavior. The loopback fixture
deliberately cannot validate these production-specific conditions.

Older versions have no Sparkle updater, so the first updater-enabled version
still needs one manual installation. Apple notarization is not a promise that
macOS will never ask again for Input Monitoring permission.

## References

- [Sparkle setup and distribution](https://sparkle-project.org/documentation/)
- [Programmatic setup](https://sparkle-project.org/documentation/programmatic-setup/)
- [Configuration keys and manual-update policy](https://sparkle-project.org/documentation/customization/)
- [Publishing feeds](https://sparkle-project.org/documentation/publishing/)
- [Signing embedded components](https://sparkle-project.org/documentation/sandboxing/)
