#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
APP_DIR="${1:-${PROJECT_DIR}/.build/Codex Voice 3.app}"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"

cd "${PROJECT_DIR}"
swift build -c release --product codex-voice-menu

/bin/rm -rf "${APP_DIR}"
/bin/mkdir -p "${MACOS_DIR}"
/bin/cp ".build/release/codex-voice-menu" "${MACOS_DIR}/Codex Voice 3"
/bin/cp "Resources/CodexVoiceRemote-Info.plist" "${CONTENTS_DIR}/Info.plist"
/usr/bin/codesign --force --sign - "${APP_DIR}"

print "${APP_DIR}"
