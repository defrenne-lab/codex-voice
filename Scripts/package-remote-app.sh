#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
APP_PATH="${PROJECT_DIR}/.build/Codex Voice 3.app"
APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${PROJECT_DIR}/Resources/CodexVoiceRemote-Info.plist")"
ARCHIVE_PATH="${1:-${PROJECT_DIR}/.build/Codex-Voice-3-v${APP_VERSION}-macOS.dmg}"
STAGING_DIR=""

cleanup() {
  if [[ -n "${STAGING_DIR}" ]]; then
    /bin/rm -rf "${STAGING_DIR}"
  fi
}
trap cleanup EXIT

cd "${PROJECT_DIR}"
"${SCRIPT_DIR}/build-remote-app.sh"
STAGING_DIR="$(/usr/bin/mktemp -d "${PROJECT_DIR}/.build/codex-voice-dmg.XXXXXX")"

/bin/rm -f "${ARCHIVE_PATH}"
/usr/bin/ditto "${APP_PATH}" "${STAGING_DIR}/Codex Voice 3.app"
/bin/ln -s /Applications "${STAGING_DIR}/Applications"
/usr/bin/hdiutil create \
  -quiet \
  -ov \
  -format UDZO \
  -volname "Codex Voice 3 v${APP_VERSION}" \
  -srcfolder "${STAGING_DIR}" \
  "${ARCHIVE_PATH}"

CHECKSUM_PATH="${ARCHIVE_PATH}.sha256"
/bin/rm -f "${CHECKSUM_PATH}"
/usr/bin/shasum -a 256 "${ARCHIVE_PATH}" | /usr/bin/sed "s#  ${ARCHIVE_PATH}#  $(/usr/bin/basename "${ARCHIVE_PATH}")#" > "${CHECKSUM_PATH}"

print "Archive : ${ARCHIVE_PATH}"
print "Empreinte : ${CHECKSUM_PATH}"
/bin/cat "${CHECKSUM_PATH}"
