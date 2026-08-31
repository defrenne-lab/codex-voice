#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
SERVICE_LABEL="lab.defrenne.codexvoice3.local"
APP_SUPPORT_DIR="${HOME}/Library/Application Support/Codex Voice 3"
BIN_DIR="${APP_SUPPORT_DIR}/bin"
LOG_DIR="${APP_SUPPORT_DIR}/logs"
LAUNCH_AGENTS_DIR="${HOME}/Library/LaunchAgents"
PLIST_PATH="${LAUNCH_AGENTS_DIR}/${SERVICE_LABEL}.plist"
INSTALLED_BINARY="${BIN_DIR}/codex-voice-local"
USER_ID="$(/usr/bin/id -u)"

cd "${PROJECT_DIR}"
swift build -c release --product codex-voice-local

/bin/mkdir -p "${BIN_DIR}" "${LOG_DIR}" "${LAUNCH_AGENTS_DIR}"
/bin/cp ".build/release/codex-voice-local" "${INSTALLED_BINARY}"
/bin/chmod 755 "${INSTALLED_BINARY}"
/bin/cp "Resources/${SERVICE_LABEL}.plist" "${PLIST_PATH}"

/usr/bin/plutil -replace ProgramArguments -json "[\"${INSTALLED_BINARY}\",\"--forever\"]" "${PLIST_PATH}"
/usr/bin/plutil -replace StandardOutPath -string "${LOG_DIR}/service.log" "${PLIST_PATH}"
/usr/bin/plutil -replace StandardErrorPath -string "${LOG_DIR}/service-error.log" "${PLIST_PATH}"
/usr/bin/plutil -lint "${PLIST_PATH}"

/bin/launchctl bootout "gui/${USER_ID}/${SERVICE_LABEL}" >/dev/null 2>&1 || true
bootstrap_succeeded=false
for attempt in 1 2 3 4 5; do
  if /bin/launchctl bootstrap "gui/${USER_ID}" "${PLIST_PATH}" >/dev/null 2>&1; then
    bootstrap_succeeded=true
    break
  fi
  /bin/sleep 0.5
done
if [[ "${bootstrap_succeeded}" != true ]]; then
  /bin/launchctl bootstrap "gui/${USER_ID}" "${PLIST_PATH}" || true
  print -u2 "Impossible d'activer ${SERVICE_LABEL} après cinq tentatives."
  exit 1
fi
/bin/launchctl kickstart -k "gui/${USER_ID}/${SERVICE_LABEL}"

print "Service installé : ${SERVICE_LABEL}"
print "Binaire : ${INSTALLED_BINARY}"
print "Logs : ${LOG_DIR}"
