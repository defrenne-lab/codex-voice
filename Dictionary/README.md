# Pronunciation dictionary

`pronunciations.fr-FR.csv` is the public, versioned reference dictionary shipped with Codex Voice 3. The runtime uses a separate mutable copy at:

```text
~/Library/Application Support/Codex Voice 3/pronunciations.csv
```

The first line must be `source,replacement`. Empty lines and lines beginning with `#` are ignored. Matching is case-insensitive and applies to whole words; when a source appears more than once, the last entry wins.

The menu-bar app opens a local working copy in TextEdit and synchronizes saved changes to the runtime through the authenticated control channel. It does not commit those changes to GitHub automatically.

To refresh this repository snapshot deliberately, run on the Mac that hosts the runtime:

```shell
Scripts/snapshot-pronunciation-dictionary.sh
```

Review the diff before committing. This repository is public: never put private project names, credentials, hostnames, personal data or other secrets in the dictionary.
