#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
SOURCE_FILE="${1:-${HOME}/Library/Application Support/Codex Voice 3/pronunciations.csv}"
REFERENCE_FILE="${PROJECT_DIR}/Dictionary/pronunciations.fr-FR.csv"

if [[ ! -r "${SOURCE_FILE}" ]]; then
  print -u2 "Dictionnaire introuvable : ${SOURCE_FILE}"
  exit 1
fi

if ! /usr/bin/grep -Eq '^source,replacement\r?$' "${SOURCE_FILE}"; then
  print -u2 "Format invalide : l’en-tête source,replacement est absent."
  exit 2
fi

if /usr/bin/cmp -s "${SOURCE_FILE}" "${REFERENCE_FILE}"; then
  print "La référence GitHub est déjà à jour."
  exit 0
fi

/bin/cp "${SOURCE_FILE}" "${REFERENCE_FILE}"
print "Référence mise à jour : ${REFERENCE_FILE}"
print "Vérifier maintenant le diff avant de créer un commit Git."
