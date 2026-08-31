#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
APP_PATH="${PROJECT_DIR}/.build/Codex Voice 3.app"
ARCHIVE_PATH="${1:-${PROJECT_DIR}/.build/Codex-Voice-3-macOS.zip}"

cd "${PROJECT_DIR}"
"${SCRIPT_DIR}/build-remote-app.sh"

/bin/rm -f "${ARCHIVE_PATH}"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "${APP_PATH}" "${ARCHIVE_PATH}"

CHECKSUM_PATH="${ARCHIVE_PATH}.sha256"
/bin/rm -f "${CHECKSUM_PATH}"
/usr/bin/shasum -a 256 "${ARCHIVE_PATH}" | /usr/bin/sed "s#  ${ARCHIVE_PATH}#  $(/usr/bin/basename "${ARCHIVE_PATH}")#" > "${CHECKSUM_PATH}"

print "Archive : ${ARCHIVE_PATH}"
print "Empreinte : ${CHECKSUM_PATH}"
/bin/cat "${CHECKSUM_PATH}"
