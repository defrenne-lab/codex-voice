#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
APP_DIR="${1:-${PROJECT_DIR}/.build/Codex Voice 3.app}"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
LOCAL_SIGNING_IDENTITY="Codex Voice 3 Local Signing"
SIGNING_IDENTITY="${CODEX_VOICE_SIGNING_IDENTITY:-}"
SIGNING_IDENTITY_FILE="${CODEX_VOICE_SIGNING_IDENTITY_FILE:-${PROJECT_DIR}/.signing-identity.local}"

if [[ -z "${SIGNING_IDENTITY}" && -r "${SIGNING_IDENTITY_FILE}" ]]; then
  IFS= read -r SIGNING_IDENTITY < "${SIGNING_IDENTITY_FILE}" || true
fi

if [[ -z "${SIGNING_IDENTITY}" ]]; then
  AVAILABLE_IDENTITIES="$(/usr/bin/security find-identity -v -p codesigning 2>/dev/null || true)"
  if [[ "${AVAILABLE_IDENTITIES}" == *"\"${LOCAL_SIGNING_IDENTITY}\""* ]]; then
    SIGNING_IDENTITY="${LOCAL_SIGNING_IDENTITY}"
  else
    SIGNING_IDENTITY="-"
  fi
fi

cd "${PROJECT_DIR}"
swift build -c release --product codex-voice-menu

/bin/rm -rf "${APP_DIR}"
/bin/mkdir -p "${MACOS_DIR}"
/bin/cp ".build/release/codex-voice-menu" "${MACOS_DIR}/Codex Voice 3"
/bin/cp "Resources/CodexVoiceRemote-Info.plist" "${CONTENTS_DIR}/Info.plist"
/usr/bin/codesign --force --sign "${SIGNING_IDENTITY}" "${APP_DIR}"

print "${APP_DIR}"
print "Signature : ${SIGNING_IDENTITY}"
