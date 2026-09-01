# Codex Voice 3 v0.1.4

Automatic SSH tunnel management for the MacBook controller.

## Added

- Voice Remote reads its SSH destination from the private MacBook file `~/.codex-voice/.env`.
- The app starts the localhost tunnel automatically, maintains it with SSH keep-alives and retries after network interruptions.
- Existing offline feedback reports common SSH failures without adding a new configuration screen.
- The SSH destination is validated before process launch, and authentication stays key-only with no stored or interactive password.

Create the MacBook configuration once:

```shell
printf '%s\n' 'CODEX_VOICE_SSH_TARGET=<mini-user>@<mini-host>' > ~/.codex-voice/.env
chmod 600 ~/.codex-voice/.env
```

Make one normal SSH connection before the first automatic launch to accept the host key and confirm that key authentication works. The Mac mini service is unchanged from v0.1.3; only the MacBook controller needs this update.
