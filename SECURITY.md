# Security

## Supported version

Codex Voice 3 is currently an early developer preview. Security fixes are applied to the latest release and the `main` branch.

## Reporting a vulnerability

Please use GitHub's private security-advisory flow for this repository when available. Do not include bearer tokens, Codex transcripts, private hostnames or other personal data in a public issue.

## Trust boundaries

The v0.1 control server listens only on `127.0.0.1` and is intended to be reached through SSH. It must not be rebound or forwarded to an untrusted network without adding TLS and an explicit device-pairing model.

The file `~/.codex-voice/control-token` is a bearer credential. Anyone who obtains it and can reach the control endpoint can change voice state, volume or interrupt audio. Keep its permissions at `0600`, transfer it only through an authenticated channel, and rotate it if it may have been disclosed.

The GitHub release is ad-hoc signed and is not notarized by Apple. Verify the release origin and the attached SHA-256 checksum before first launch.
