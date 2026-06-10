#!/usr/bin/env bash
set -euo pipefail

# Build, sign, notarize, staple, and package a Developer ID release of Vibes.app,
# then stage the Sparkle update artifact and matching release notes.
#
# This script is intentionally fail-fast: it refuses to proceed without the
# signing/notarization inputs a real release requires. It does NOT touch any
# private key material beyond what xcodebuild/notarytool read from the Keychain.
#
# Usage:
#   cp .env.release.example .env.release   # then fill it in
#   scripts/release-mac.sh
#
# Or pass everything via the environment. See REQUIRED_VARS below.

# Anchor to the repo root so relative paths work regardless of the caller's CWD.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "${SCRIPT_DIR}")"
cd "${REPO_ROOT}"

# A VIBES_BUILD_DMG set in the environment (e.g. by the Makefile's mac-release
# target) must win over .env.release; otherwise the file silently downgrades a
# requested DMG build to a zip-only one.
_env_build_dmg_set="${VIBES_BUILD_DMG+1}"
_env_build_dmg="${VIBES_BUILD_DMG:-}"

ENV_FILE="${RELEASE_ENV_FILE:-.env.release}"
if [[ -f "${ENV_FILE}" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "${ENV_FILE}"
  set +a
fi

[[ -n "${_env_build_dmg_set}" ]] && export VIBES_BUILD_DMG="${_env_build_dmg}"

die() { echo "error: $*" >&2; exit 2; }
note() { echo "==> $*"; }

# --- Inputs -----------------------------------------------------------------

REQUIRED_VARS=(
  VIBES_BUNDLE_ID            # reverse-DNS app id, e.g. app.vibes.mac
  VIBES_DEVELOPMENT_TEAM     # Apple Developer Team ID, e.g. J23CYSN68B
  VIBES_CODESIGN_IDENTITY    # e.g. "Developer ID Application: Your Name (TEAMID)"
  VIBES_NOTARY_PROFILE       # notarytool keychain profile name (see setup-notary.sh)
  VIBES_RELEASE_VERSION      # marketing version, e.g. 0.2.0
  VIBES_BUILD_NUMBER         # monotonically increasing integer
  VIBES_APPCAST_BASE_URL     # public URL prefix for update archives (no trailing slash)
)

missing=()
for var in "${REQUIRED_VARS[@]}"; do
  [[ -n "${!var:-}" ]] || missing+=("${var}")
done
if (( ${#missing[@]} > 0 )); then
  echo "error: missing required environment variables:" >&2
  printf '  - %s\n' "${missing[@]}" >&2
  echo "Copy .env.release.example to .env.release and fill it in, or export them." >&2
  exit 2
fi

PROJECT="client/Vibes.xcodeproj"
SCHEME="Vibes"
APP_NAME="Vibes"
BUILD_DIR="build"
ARCHIVE_PATH="${BUILD_DIR}/${APP_NAME}.xcarchive"
EXPORT_DIR="${BUILD_DIR}/export"
NOTARY_DIR="${BUILD_DIR}/notary"
APP_PATH="${EXPORT_DIR}/${APP_NAME}.app"
EXPORT_OPTIONS="scripts/ExportOptions.plist"
APPCAST_STAGING="release/appcast"
RELEASE_NOTES_SRC="release/release-notes/${VIBES_RELEASE_VERSION}.md"
UPDATE_ZIP="${APPCAST_STAGING}/${APP_NAME}-${VIBES_RELEASE_VERSION}.zip"

# --- Preflight: credentials, version sync, EdDSA key match (fail fast) -------
# All cheap checks run here, before the slow archive + double notarization:
# required vars, version sync, release notes, signing identity, notary profile,
# and that the EdDSA key's public half equals the app's SUPublicEDKey. A missing
# or mismatched credential dies in milliseconds instead of after minutes of work.
# Inherits VIBES_ED_KEY_FILE if the caller set it. See preflight-release.sh.
"${SCRIPT_DIR}/preflight-release.sh"

[[ -f "${EXPORT_OPTIONS}" ]] || die "missing ${EXPORT_OPTIONS}"

note "Releasing ${APP_NAME} ${VIBES_RELEASE_VERSION} (build ${VIBES_BUILD_NUMBER}) as ${VIBES_BUNDLE_ID}"

# --- Clean and build an archive ---------------------------------------------

rm -rf "${ARCHIVE_PATH}" "${EXPORT_DIR}" "${NOTARY_DIR}"
mkdir -p "${BUILD_DIR}" "${NOTARY_DIR}" "${APPCAST_STAGING}"

note "Archiving..."
xcodebuild archive \
  -project "${PROJECT}" \
  -scheme "${SCHEME}" \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "${ARCHIVE_PATH}" \
  MARKETING_VERSION="${VIBES_RELEASE_VERSION}" \
  CURRENT_PROJECT_VERSION="${VIBES_BUILD_NUMBER}" \
  PRODUCT_BUNDLE_IDENTIFIER="${VIBES_BUNDLE_ID}" \
  DEVELOPMENT_TEAM="${VIBES_DEVELOPMENT_TEAM}" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="${VIBES_CODESIGN_IDENTITY}"

# --- Export a Developer ID app ----------------------------------------------

note "Exporting Developer ID app..."
xcodebuild -exportArchive \
  -archivePath "${ARCHIVE_PATH}" \
  -exportPath "${EXPORT_DIR}" \
  -exportOptionsPlist "${EXPORT_OPTIONS}"

[[ -d "${APP_PATH}" ]] || die "export did not produce ${APP_PATH}"

# --- Notarize and staple the app --------------------------------------------

note "Notarizing app (this can take a few minutes)..."
ditto -c -k --keepParent "${APP_PATH}" "${NOTARY_DIR}/${APP_NAME}-app.zip"
xcrun notarytool submit "${NOTARY_DIR}/${APP_NAME}-app.zip" \
  --keychain-profile "${VIBES_NOTARY_PROFILE}" --wait
xcrun stapler staple "${APP_PATH}"

# --- Verify signature and Gatekeeper assessment -----------------------------

note "Verifying signature and Gatekeeper assessment..."
codesign --verify --deep --strict --verbose=2 "${APP_PATH}"
spctl --assess --type execute --verbose "${APP_PATH}"

# --- Package the Sparkle update zip -----------------------------------------

note "Packaging Sparkle update zip..."
rm -f "${UPDATE_ZIP}"
# ditto preserves code signatures and symlinks inside the bundle.
ditto -c -k --keepParent "${APP_PATH}" "${UPDATE_ZIP}"

# --- Optional DMG (first-download artifact) ---------------------------------

if [[ "${VIBES_BUILD_DMG:-0}" == "1" ]]; then
  DMG_PATH="${BUILD_DIR}/${APP_NAME}-${VIBES_RELEASE_VERSION}.dmg"
  note "Building DMG ${DMG_PATH}..."
  DMG_STAGE="${BUILD_DIR}/dmg-stage"
  rm -rf "${DMG_STAGE}" "${DMG_PATH}"
  mkdir -p "${DMG_STAGE}"
  ditto "${APP_PATH}" "${DMG_STAGE}/${APP_NAME}.app"
  ln -s /Applications "${DMG_STAGE}/Applications"
  hdiutil create -volname "${APP_NAME}" -srcfolder "${DMG_STAGE}" -ov -format UDZO "${DMG_PATH}"
  note "Signing DMG..."
  codesign --force --sign "${VIBES_CODESIGN_IDENTITY}" --timestamp "${DMG_PATH}"
  note "Notarizing DMG..."
  xcrun notarytool submit "${DMG_PATH}" --keychain-profile "${VIBES_NOTARY_PROFILE}" --wait
  xcrun stapler staple "${DMG_PATH}"
  codesign --verify --verbose=2 "${DMG_PATH}"
  spctl --assess --type open --context context:primary-signature --verbose "${DMG_PATH}"
  note "DMG ready: ${DMG_PATH}"
fi

# --- Stage release notes alongside the update archive -----------------------

cp "${RELEASE_NOTES_SRC}" "${APPCAST_STAGING}/"

cat <<EOF

Release build complete.

  App bundle:     ${APP_PATH}
  Update zip:     ${UPDATE_ZIP}
  Release notes:  ${APPCAST_STAGING}/$(basename "${RELEASE_NOTES_SRC}")
  Download URL:   ${VIBES_APPCAST_BASE_URL}/$(basename "${UPDATE_ZIP}")

Next:
  1. scripts/generate-appcast.sh   # sign + regenerate release/appcast/appcast.xml
  2. Upload the update zip (and DMG, if built) to the release host.
  3. Publish release/appcast/appcast.xml to the public appcast URL.
EOF
