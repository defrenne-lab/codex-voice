# Shared by the two zsh build scripts. This file does not modify the Keychain.
# PROJECT_DIR must be set by the caller.

DISTRIBUTION_BUILD="${CODEX_VOICE_DISTRIBUTION:-0}"
if [[ "${DISTRIBUTION_BUILD}" != 0 && "${DISTRIBUTION_BUILD}" != 1 ]]; then
  print -u2 'CODEX_VOICE_DISTRIBUTION doit valoir 0 ou 1.'
  exit 1
fi

SIGNING_IDENTITY="${CODEX_VOICE_SIGNING_IDENTITY:-}"
SIGNING_OPTIONS=()
if [[ "${DISTRIBUTION_BUILD}" == 1 ]]; then
  DEFAULT_IDENTITY_FILE="${PROJECT_DIR}/.developer-id.local"
else
  DEFAULT_IDENTITY_FILE="${PROJECT_DIR}/.signing-identity.local"
fi
SIGNING_IDENTITY_FILE="${CODEX_VOICE_SIGNING_IDENTITY_FILE:-${DEFAULT_IDENTITY_FILE}}"
if [[ -z "${SIGNING_IDENTITY}" && -r "${SIGNING_IDENTITY_FILE}" ]]; then
  IFS= read -r SIGNING_IDENTITY < "${SIGNING_IDENTITY_FILE}" || true
fi

if [[ "${DISTRIBUTION_BUILD}" == 1 ]]; then
  if [[ -z "${SIGNING_IDENTITY}" || "${SIGNING_IDENTITY}" == '-' ]]; then
    print -u2 'Distribution : préciser un certificat Developer ID Application ; aucun repli vers une signature de développement.'
    exit 1
  fi

  # Resolve an exact name or SHA-1 to a valid Developer ID identity. In
  # particular, never fall back to another project's Apple Development key.
  AVAILABLE_IDENTITIES="$(/usr/bin/security find-identity -v -p codesigning)"
  RESOLVED_IDENTITY="$(print -r -- "${AVAILABLE_IDENTITIES}" | /usr/bin/awk -v selected="${SIGNING_IDENTITY}" '
    /"Developer ID Application: / {
      name = $0
      sub(/^[^"]*"/, "", name)
      sub(/"[[:space:]]*$/, "", name)
      if ($2 == selected || name == selected) { print $2 }
    }
  ')"
  if [[ -z "${RESOLVED_IDENTITY}" || "${RESOLVED_IDENTITY}" == *$'\n'* ]]; then
    print -u2 'Distribution : certificat Developer ID Application absent, invalide ou ambigu dans le trousseau.'
    exit 1
  fi
  SIGNING_IDENTITY="${RESOLVED_IDENTITY}"
  SIGNING_OPTIONS=(--options runtime --timestamp)
elif [[ -z "${SIGNING_IDENTITY}" ]]; then
  LOCAL_SIGNING_IDENTITY='Codex Voice 3 Local Signing'
  AVAILABLE_IDENTITIES="$(/usr/bin/security find-identity -v -p codesigning 2>/dev/null || true)"
  if [[ "${AVAILABLE_IDENTITIES}" == *"\"${LOCAL_SIGNING_IDENTITY}\""* ]]; then
    SIGNING_IDENTITY="${LOCAL_SIGNING_IDENTITY}"
  else
    SIGNING_IDENTITY='-'
  fi
fi
