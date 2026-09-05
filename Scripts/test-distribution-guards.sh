#!/bin/zsh

set -euo pipefail
SCRIPT_DIR="${0:A:h}"

expect_refusal() {
  local label="$1"
  local expected="$2"
  shift 2
  local output
  if output="$("$@" 2>&1)"; then
    print -u2 "ÉCHEC : ${label} a été accepté."
    exit 1
  fi
  if [[ "${output}" != *"${expected}"* ]]; then
    print -u2 "ÉCHEC : ${label} a échoué pour une autre raison : ${output}"
    exit 1
  fi
  print "OK : ${label}"
}

expect_refusal 'mode inconnu' 'doit valoir 0 ou 1' \
  /usr/bin/env CODEX_VOICE_DISTRIBUTION=typo /bin/zsh "${SCRIPT_DIR}/build-remote-app.sh"
expect_refusal 'identité absente' 'préciser un certificat Developer ID Application' \
  /usr/bin/env CODEX_VOICE_DISTRIBUTION=1 CODEX_VOICE_SIGNING_IDENTITY= \
  CODEX_VOICE_SIGNING_IDENTITY_FILE=/dev/null /bin/zsh "${SCRIPT_DIR}/build-remote-app.sh"
expect_refusal 'signature ad-hoc' 'préciser un certificat Developer ID Application' \
  /usr/bin/env CODEX_VOICE_DISTRIBUTION=1 CODEX_VOICE_SIGNING_IDENTITY=- \
  /bin/zsh "${SCRIPT_DIR}/build-remote-app.sh"
expect_refusal 'identité de développement' 'absent, invalide ou ambigu' \
  /usr/bin/env CODEX_VOICE_DISTRIBUTION=1 \
  CODEX_VOICE_SIGNING_IDENTITY='Apple Development: not-a-distribution-identity' \
  /bin/zsh "${SCRIPT_DIR}/build-remote-app.sh"
expect_refusal 'app installée hors des sorties de build' 'destination doit être un bundle .app' \
  /bin/zsh "${SCRIPT_DIR}/build-remote-app.sh" '/Applications/Codex Voice 3.app'
expect_refusal 'racine de build comme bundle' 'destination doit être un bundle .app' \
  /bin/zsh "${SCRIPT_DIR}/build-remote-app.sh" "${SCRIPT_DIR:h}/.build"
expect_refusal 'image hors des sorties de build' 'destination doit être un fichier .dmg' \
  /bin/zsh "${SCRIPT_DIR}/package-remote-app.sh" '/Applications/Codex Voice 3.dmg'
expect_refusal 'dossier arbitraire comme image' 'destination doit être un fichier .dmg' \
  /bin/zsh "${SCRIPT_DIR}/package-remote-app.sh" "${SCRIPT_DIR:h}/.build"
