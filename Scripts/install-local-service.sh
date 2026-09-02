#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
SERVICE_LABEL="lab.defrenne.codexvoice3.local"
APP_SUPPORT_DIR="${HOME}/Library/Application Support/Codex Voice 3"
BIN_DIR="${APP_SUPPORT_DIR}/bin"
LOG_DIR="${APP_SUPPORT_DIR}/logs"
PRONUNCIATION_FILE="${APP_SUPPORT_DIR}/pronunciations.csv"
LEGACY_PRONUNCIATION_FILE="${HOME}/Library/Application Support/Codex Voice 2/pronunciations.csv"
PACKAGED_PRONUNCIATION_FILE="${PROJECT_DIR}/Dictionary/pronunciations.fr-FR.csv"
LAUNCH_AGENTS_DIR="${HOME}/Library/LaunchAgents"
PLIST_PATH="${LAUNCH_AGENTS_DIR}/${SERVICE_LABEL}.plist"
INSTALLED_BINARY="${BIN_DIR}/codex-voice-local"
INSTALLED_CONTROL_BINARY="${BIN_DIR}/codex-voice-remote"
USER_ID="$(/usr/bin/id -u)"

cd "${PROJECT_DIR}"
swift build -c release --product codex-voice-local
swift build -c release --product codex-voice-remote

/bin/mkdir -p "${BIN_DIR}" "${LOG_DIR}" "${LAUNCH_AGENTS_DIR}"
/bin/cp ".build/release/codex-voice-local" "${INSTALLED_BINARY}"
/bin/cp ".build/release/codex-voice-remote" "${INSTALLED_CONTROL_BINARY}"
/bin/chmod 755 "${INSTALLED_BINARY}"
/bin/chmod 755 "${INSTALLED_CONTROL_BINARY}"
/bin/cp "Resources/${SERVICE_LABEL}.plist" "${PLIST_PATH}"

if [[ ! -f "${PRONUNCIATION_FILE}" ]]; then
  if [[ -f "${LEGACY_PRONUNCIATION_FILE}" ]]; then
    /bin/cp "${LEGACY_PRONUNCIATION_FILE}" "${PRONUNCIATION_FILE}"
    print "Dictionnaire V2 migré : ${PRONUNCIATION_FILE}"
  else
    /bin/cp "${PACKAGED_PRONUNCIATION_FILE}" "${PRONUNCIATION_FILE}"
    print "Dictionnaire installé : ${PRONUNCIATION_FILE}"
  fi
fi

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
print "Contrôleur : ${INSTALLED_CONTROL_BINARY}"
print "Dictionnaire : ${PRONUNCIATION_FILE}"
print "Logs : ${LOG_DIR}"
