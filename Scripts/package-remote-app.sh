#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
APP_PATH="${PROJECT_DIR}/.build/Codex Voice 3.app"
APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${PROJECT_DIR}/Resources/CodexVoiceRemote-Info.plist")"
ARCHIVE_PATH="${1:-${PROJECT_DIR}/.build/Codex-Voice-3-v${APP_VERSION}-macOS.dmg}"
ARCHIVE_PATH="${ARCHIVE_PATH:A}"
if [[ "${ARCHIVE_PATH}" != "${PROJECT_DIR}/.build/"* || "${ARCHIVE_PATH}" != *.dmg || -d "${ARCHIVE_PATH}" ]]; then
  print -u2 'La destination doit être un fichier .dmg dans le dossier .build du projet.'
  exit 1
fi
STAGING_DIR=""
source "${SCRIPT_DIR}/signing-configuration.sh"

cleanup() {
  if [[ -n "${STAGING_DIR}" ]]; then
    /bin/rm -rf "${STAGING_DIR}"
  fi
}
trap cleanup EXIT

cd "${PROJECT_DIR}"
CODEX_VOICE_SIGNING_IDENTITY="${SIGNING_IDENTITY}" \
  CODEX_VOICE_DISTRIBUTION="${DISTRIBUTION_BUILD}" \
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

if [[ "${DISTRIBUTION_BUILD}" == 1 ]]; then
  /usr/bin/codesign --force --timestamp --sign "${SIGNING_IDENTITY}" "${ARCHIVE_PATH}"
  /usr/bin/codesign --verify --strict --verbose=2 "${ARCHIVE_PATH}"
  print 'Developer ID : signature vérifiée, notarisation encore nécessaire avant toute publication.'
fi

CHECKSUM_PATH="${ARCHIVE_PATH}.sha256"
/bin/rm -f "${CHECKSUM_PATH}"
/usr/bin/shasum -a 256 "${ARCHIVE_PATH}" | /usr/bin/sed "s#  ${ARCHIVE_PATH}#  $(/usr/bin/basename "${ARCHIVE_PATH}")#" > "${CHECKSUM_PATH}"

print "Archive : ${ARCHIVE_PATH}"
print "Empreinte : ${CHECKSUM_PATH}"
/bin/cat "${CHECKSUM_PATH}"
