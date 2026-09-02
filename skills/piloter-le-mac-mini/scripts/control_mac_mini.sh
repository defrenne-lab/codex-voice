#!/bin/zsh

set -euo pipefail

CONTROL_BINARY="${CODEX_VOICE_CONTROL_BIN:-${HOME}/Library/Application Support/Codex Voice 3/bin/codex-voice-remote}"
TOKEN_FILE="${CODEX_VOICE_TOKEN_FILE:-${HOME}/.codex-voice/control-token}"

usage() {
  print -u2 "Usage: control_mac_mini.sh status | volume 0..100 | voice-speed slow|normal|fast|very-fast | voice-on | voice-off | stop"
}

require_percentage() {
  local value="${1:-}"
  if [[ ! "${value}" =~ '^[0-9]+$' ]] || (( value < 0 || value > 100 )); then
    print -u2 "Le volume doit être un entier compris entre 0 et 100."
    exit 2
  fi
}

require_voice_control() {
  if [[ ! -x "${CONTROL_BINARY}" ]]; then
    print -u2 "Contrôleur Codex Voice introuvable : ${CONTROL_BINARY}"
    print -u2 "Réinstaller le service local depuis le dépôt Codex Voice 3."
    exit 3
  fi
  if [[ ! -r "${TOKEN_FILE}" ]]; then
    print -u2 "Jeton de contrôle Codex Voice introuvable : ${TOKEN_FILE}"
    exit 3
  fi
}

voice_control() {
  require_voice_control
  "${CONTROL_BINARY}" --token-file "${TOKEN_FILE}" "$@"
}

command="${1:-}"
case "${command}" in
  status)
    voice_control state
    ;;
  volume|system-volume|voice-volume)
    percentage="${2:-}"
    require_percentage "${percentage}"
    normalized="$(/usr/bin/awk -v percent="${percentage}" 'BEGIN { printf "%.2f", percent / 100 }')"
    voice_control volume "${normalized}"
    ;;
  voice-speed)
    case "${2:-}" in
      slow) rate="0.38" ;;
      normal) rate="0.48" ;;
      fast) rate="0.53" ;;
      very-fast) rate="0.58" ;;
      *)
        print -u2 "La vitesse doit être slow, normal, fast ou very-fast."
        exit 2
        ;;
    esac
    voice_control rate "${rate}"
    ;;
  voice-on)
    voice_control enable
    ;;
  voice-off)
    voice_control disable
    ;;
  stop)
    voice_control interrupt
    ;;
  *)
    usage
    exit 2
    ;;
esac
