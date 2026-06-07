#!/usr/bin/env bash
set -euo pipefail

# Sign update archives and (re)generate release/appcast/appcast.xml using
# Sparkle's generate_appcast tool. Run after scripts/release-mac.sh has staged
# a new update zip and release notes under release/appcast/.
#
# generate_appcast signs each archive with the EdDSA private key stored in your
# Keychain (the one created by Sparkle's generate_keys), embeds the signature,
# length, and minimum system version, and writes the appcast XML.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "${SCRIPT_DIR}")"
cd "${REPO_ROOT}"

ENV_FILE="${RELEASE_ENV_FILE:-.env.release}"
if [[ -f "${ENV_FILE}" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "${ENV_FILE}"
  set +a
fi

die() { echo "error: $*" >&2; exit 2; }
note() { echo "==> $*"; }

: "${VIBES_APPCAST_BASE_URL:?VIBES_APPCAST_BASE_URL is required (public URL prefix for update archives, no trailing slash)}"

APPCAST_STAGING="release/appcast"
APPCAST_XML="${APPCAST_STAGING}/appcast.xml"
[[ -d "${APPCAST_STAGING}" ]] || die "missing ${APPCAST_STAGING}; run scripts/release-mac.sh first"

# --- Locate generate_appcast ------------------------------------------------

find_generate_appcast() {
  # 1) Explicit override: an unpacked Sparkle distribution.
  if [[ -n "${SPARKLE_BIN:-}" ]]; then
    if [[ -x "${SPARKLE_BIN}/generate_appcast" ]]; then
      echo "${SPARKLE_BIN}/generate_appcast"; return 0
    fi
    die "SPARKLE_BIN is set (${SPARKLE_BIN}) but ${SPARKLE_BIN}/generate_appcast is not executable"
  fi

  # 2) On PATH.
  if command -v generate_appcast >/dev/null 2>&1; then
    command -v generate_appcast; return 0
  fi

  # 3) Local fallback: SwiftPM artifact under DerivedData after package resolution.
  local hit
  hit="$(find "${HOME}/Library/Developer/Xcode/DerivedData" \
    -type f -name generate_appcast -path '*artifacts*' 2>/dev/null | head -1)"
  if [[ -n "${hit}" ]]; then
    echo "${hit}"; return 0
  fi

  return 1
}

GENERATE_APPCAST="$(find_generate_appcast)" || die \
"could not find Sparkle's generate_appcast.
Set SPARKLE_BIN to an unpacked Sparkle release's bin/ directory
(download from https://github.com/sparkle-project/Sparkle/releases),
or build the app once so SwiftPM resolves the Sparkle artifact."

note "Using generate_appcast: ${GENERATE_APPCAST}"

# --- Generate ----------------------------------------------------------------
#
# By default generate_appcast reads the EdDSA private key from the login
# Keychain. The first time a given tool binary touches the key, macOS shows a
# GUI authorization prompt — fine interactively (click "Always Allow"), but it
# hangs headless/CI runs. Set VIBES_ED_KEY_FILE to a private-key file (exported
# once via Sparkle's `generate_keys -x`) to sign non-interactively instead.

key_args=()
if [[ -n "${VIBES_ED_KEY_FILE:-}" ]]; then
  [[ -f "${VIBES_ED_KEY_FILE}" ]] || die "VIBES_ED_KEY_FILE is set but not a file: ${VIBES_ED_KEY_FILE}"
  key_args=(--ed-key-file "${VIBES_ED_KEY_FILE}")
  note "Signing with key file ${VIBES_ED_KEY_FILE}"
else
  note "Signing with Keychain key (approve the macOS prompt if it appears)"
fi

note "Generating appcast from ${APPCAST_STAGING} with download prefix ${VIBES_APPCAST_BASE_URL}"
"${GENERATE_APPCAST}" \
  "${key_args[@]}" \
  --download-url-prefix "${VIBES_APPCAST_BASE_URL}/" \
  "${APPCAST_STAGING}"

[[ -f "${APPCAST_XML}" ]] || die "generate_appcast did not produce ${APPCAST_XML}"

# --- Validate the result ----------------------------------------------------

note "Validating ${APPCAST_XML}"
problems=()
grep -q 'sparkle:edSignature=' "${APPCAST_XML}" || problems+=("no EdDSA signature found")
grep -q 'length=' "${APPCAST_XML}" || problems+=("no archive length found")
grep -qE '<sparkle:version>[0-9]' "${APPCAST_XML}" || problems+=("no sparkle:version (build number) found")
grep -q 'url=' "${APPCAST_XML}" || problems+=("no archive URL found")
grep -q 'sparkle:minimumSystemVersion' "${APPCAST_XML}" \
  || echo "warning: no sparkle:minimumSystemVersion in appcast; confirm the bundle declares LSMinimumSystemVersion (>= 14.0)" >&2

if (( ${#problems[@]} > 0 )); then
  printf 'error: appcast validation failed:\n' >&2
  printf '  - %s\n' "${problems[@]}" >&2
  exit 1
fi

cat <<EOF

Appcast generated and validated: ${APPCAST_XML}

Upload these to the release host / appcast URL:
EOF
ls -1 "${APPCAST_STAGING}"
