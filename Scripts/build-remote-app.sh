#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
APP_DIR="${1:-${PROJECT_DIR}/.build/Codex Voice 3.app}"
# Only disposable build outputs may be replaced, never an installed app or
# an arbitrary directory supplied by mistake.
APP_DIR="${APP_DIR:A}"
if [[ "${APP_DIR}" != "${PROJECT_DIR}/.build/"* || "${APP_DIR}" != *.app ]]; then
  print -u2 'La destination doit être un bundle .app dans le dossier .build du projet.'
  exit 1
fi
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
source "${SCRIPT_DIR}/signing-configuration.sh"

cd "${PROJECT_DIR}"
swift build -c release --product codex-voice-menu

# SwiftPM links Sparkle, but does not assemble our .app bundle. Preserve all
# framework symlinks, helpers, localizations and executable permissions.
SPARKLE_ROOT="${PROJECT_DIR}/.build/artifacts/sparkle/Sparkle"
SPARKLE_SOURCE="${SPARKLE_ROOT}/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
if [[ ! -d "${SPARKLE_SOURCE}" || ! -f "${SPARKLE_ROOT}/LICENSE" ]]; then
  print -u2 'Le framework Sparkle ou sa licence est absent des dépendances SwiftPM.'
  exit 1
fi

/bin/rm -rf "${APP_DIR}"
/bin/mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}" "${CONTENTS_DIR}/Frameworks"
/bin/cp ".build/release/codex-voice-menu" "${MACOS_DIR}/Codex Voice 3"
/bin/cp "Resources/CodexVoiceRemote-Info.plist" "${CONTENTS_DIR}/Info.plist"
/bin/cp "Resources/CodexVoice3.icns" "${RESOURCES_DIR}/CodexVoice3.icns"
/bin/cp "${SPARKLE_ROOT}/LICENSE" "${RESOURCES_DIR}/Sparkle-LICENSE.txt"
/usr/bin/ditto "${SPARKLE_SOURCE}" "${CONTENTS_DIR}/Frameworks/Sparkle.framework"

# Sign nested code inside-out, never with codesign --deep. Downloader's
# existing sandbox entitlements must survive re-signing (Sparkle guidance).
SPARKLE_FRAMEWORK="${CONTENTS_DIR}/Frameworks/Sparkle.framework"
SPARKLE_VERSION="${SPARKLE_FRAMEWORK}/Versions/B"
for helper in \
  "${SPARKLE_VERSION}/XPCServices/Installer.xpc" \
  "${SPARKLE_VERSION}/XPCServices/Downloader.xpc" \
  "${SPARKLE_VERSION}/Autoupdate" \
  "${SPARKLE_VERSION}/Updater.app" \
  "${SPARKLE_FRAMEWORK}"; do
  extra_options=()
  if [[ "${helper}" == */Downloader.xpc ]]; then
    extra_options=(--preserve-metadata=entitlements)
  fi
  /usr/bin/codesign --force --sign "${SIGNING_IDENTITY}" \
    "${SIGNING_OPTIONS[@]}" "${extra_options[@]}" "${helper}"
done
/usr/bin/codesign --force --sign "${SIGNING_IDENTITY}" "${SIGNING_OPTIONS[@]}" "${APP_DIR}"
/usr/bin/codesign --verify --deep --strict --verbose=2 "${APP_DIR}"

print "${APP_DIR}"
print "Signature : ${SIGNING_IDENTITY}"
