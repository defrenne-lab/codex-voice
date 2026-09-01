# Security

## Supported version

Codex Voice 3 is currently an early developer preview. Security fixes are applied to the latest release and the `main` branch.

## Reporting a vulnerability

Please use GitHub's private security-advisory flow for this repository when available. Do not include bearer tokens, Codex transcripts, private hostnames or other personal data in a public issue.

## Trust boundaries

The v0.1 control server listens only on `127.0.0.1` and is intended to be reached through SSH. It must not be rebound or forwarded to an untrusted network without adding TLS and an explicit device-pairing model.

The file `~/.codex-voice/control-token` is a bearer credential. Anyone who obtains it and can reach the control endpoint can change voice state, volume or interrupt audio. Keep its permissions at `0600`, transfer it only through an authenticated channel, and rotate it if it may have been disclosed.

The optional MacBook file `~/.codex-voice/.env` contains the SSH destination used to create the loopback tunnel. The destination is validated before it becomes an argument to `/usr/bin/ssh`. The app enables batch mode, so it can use an existing SSH key but cannot store or prompt for a password. Keep the file local and at `0600`; do not commit private hostnames or account names.

Starting with v0.1.5, the GitHub release uses a stable Apple Development signature so successive builds share a designated requirement. This is not a Developer ID distribution signature and the app is not notarized by Apple. Verify the release origin and the attached SHA-256 checksum before first launch.
