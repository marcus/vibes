#!/usr/bin/env bash
set -euo pipefail

# Fast, cheap release preflight. Run BEFORE the (slow) archive + double
# notarization so a missing credential or mismatched key fails in milliseconds
# instead of after several minutes of wasted work.
#
# Checks, in order of how expensive the failure is to discover late:
#   1. Required release env vars are set.
#   2. VIBES_RELEASE_VERSION matches the project's MARKETING_VERSION.
#   2b. The active macOS SDK is >= 26 (the app's deployment target).
#   3. Release notes exist for the version.
#   4. Developer ID code-signing identity is in the keychain.
#   5. notarytool keychain profile resolves.
#   6. The EdDSA signing key (keychain or VIBES_ED_KEY_FILE) is available AND its
#      public half equals the app's SUPublicEDKey — i.e. existing users will
#      actually accept updates signed with it. This is the catastrophic one:
#      signing with the wrong key ships an update every installed app rejects.
#
# Standalone: run `scripts/preflight-release.sh` any time to check readiness
# without building anything. release-mac.sh also calls it.

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

die()  { echo "preflight error: $*" >&2; exit 2; }
note() { echo "==> $*"; }
ok()   { echo "  ✓ $*"; }

PROJECT="client/Vibes.xcodeproj"
SCHEME="Vibes"
INFO_PLIST="client/Vibes/Info.plist"

note "Release preflight"

# --- 1. Required env vars ---------------------------------------------------
REQUIRED_VARS=(
  VIBES_BUNDLE_ID VIBES_DEVELOPMENT_TEAM VIBES_CODESIGN_IDENTITY
  VIBES_NOTARY_PROFILE VIBES_RELEASE_VERSION VIBES_BUILD_NUMBER
  VIBES_APPCAST_BASE_URL
)
missing=()
for var in "${REQUIRED_VARS[@]}"; do [[ -n "${!var:-}" ]] || missing+=("${var}"); done
if (( ${#missing[@]} > 0 )); then
  printf 'preflight error: missing required environment variables:\n' >&2
  printf '  - %s\n' "${missing[@]}" >&2
  echo "Copy .env.release.example to .env.release and fill it in." >&2
  exit 2
fi
ok "release env vars set"

# --- 2. Version sync --------------------------------------------------------
project_mv="$(xcodebuild -project "${PROJECT}" -scheme "${SCHEME}" \
  -showBuildSettings -configuration Release 2>/dev/null \
  | awk -F' = ' '/ MARKETING_VERSION =/ {print $2; exit}')"
[[ "${project_mv}" == "${VIBES_RELEASE_VERSION}" ]] || die \
  "VIBES_RELEASE_VERSION (${VIBES_RELEASE_VERSION}) != project MARKETING_VERSION (${project_mv}). Bump the project first."
[[ "${VIBES_BUILD_NUMBER}" =~ ^[0-9]+$ ]] || die "VIBES_BUILD_NUMBER must be a positive integer."
ok "version ${VIBES_RELEASE_VERSION} (build ${VIBES_BUILD_NUMBER}) matches the project"

# --- 2b. Build SDK is recent enough ----------------------------------------
# The app deploys to macOS 26.0, so it must be built against the macOS 26 SDK
# or newer. Building with an older SDK silently drops the macOS 26 Liquid Glass
# APIs the app links against.
sdk_version="$(xcrun --show-sdk-version --sdk macosx 2>/dev/null || true)"
[[ -n "${sdk_version}" ]] || die "could not determine the macOS SDK version (xcrun --show-sdk-version --sdk macosx). Install the Xcode command line tools / select a current Xcode."
sdk_major="${sdk_version%%.*}"
[[ "${sdk_major}" =~ ^[0-9]+$ ]] || die "unexpected macOS SDK version string: ${sdk_version}"
(( sdk_major >= 26 )) || die "macOS SDK ${sdk_version} is too old; the app requires the macOS 26 SDK or newer. Select an Xcode that ships it: sudo xcode-select -s /Applications/Xcode.app"
ok "macOS SDK ${sdk_version} (>= 26)"

# --- 3. Release notes -------------------------------------------------------
NOTES="release/release-notes/${VIBES_RELEASE_VERSION}.md"
[[ -f "${NOTES}" ]] || die "missing release notes: ${NOTES} (create it before releasing)"
ok "release notes present"

# --- 4. Code-signing identity ----------------------------------------------
if ! security find-identity -v -p codesigning 2>/dev/null | grep -qF "${VIBES_CODESIGN_IDENTITY}"; then
  available="$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/^[[:space:]]*[0-9][0-9]*) //p')"
  die "code-signing identity not found in any keychain:
    ${VIBES_CODESIGN_IDENTITY}
Install the Developer ID Application certificate AND its private key (Xcode →
Settings → Accounts → Manage Certificates, or 'security import id.p12').
Available identities:
${available:-  (none)}"
fi
ok "signing identity present"

# --- 5. notarytool profile --------------------------------------------------
notary_out="$(xcrun notarytool history --keychain-profile "${VIBES_NOTARY_PROFILE}" 2>&1 || true)"
if grep -q "No Keychain password item found" <<<"${notary_out}"; then
  die "notarytool profile '${VIBES_NOTARY_PROFILE}' is not set up. Create it with:
  scripts/setup-notary.sh api ${VIBES_NOTARY_PROFILE} <KEY_ID> <ISSUER_ID> /path/to/AuthKey_XXXX.p8"
elif grep -qi "Successfully received submission history" <<<"${notary_out}"; then
  ok "notary profile '${VIBES_NOTARY_PROFILE}' authenticates"
else
  echo "  ! could not confirm notary profile (network?); continuing. Detail: $(head -1 <<<"${notary_out}")" >&2
fi

# --- 6. EdDSA signing key matches the app's SUPublicEDKey -------------------
expected_pub="$(/usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" "${INFO_PLIST}" 2>/dev/null || true)"
[[ -n "${expected_pub}" ]] || die "could not read SUPublicEDKey from ${INFO_PLIST}"

if [[ -n "${VIBES_ED_KEY_FILE:-}" ]]; then
  [[ -f "${VIBES_ED_KEY_FILE}" ]] || die "VIBES_ED_KEY_FILE is set but not a file: ${VIBES_ED_KEY_FILE}"
  # Derive the ed25519 public key from the 32-byte seed file (no Sparkle binary,
  # no key material printed) and compare.
  derived_pub="$(VIBES_ED_KEY_FILE="${VIBES_ED_KEY_FILE}" node -e '
    const crypto=require("crypto"),fs=require("fs");
    const seed=Buffer.from(fs.readFileSync(process.env.VIBES_ED_KEY_FILE,"utf8").trim(),"base64");
    if(seed.length!==32){process.stderr.write("seed length "+seed.length);process.exit(1);}
    const der=Buffer.concat([Buffer.from("302e020100300506032b657004220420","hex"),seed]);
    const spki=crypto.createPublicKey({key:der,format:"der",type:"pkcs8"}).export({format:"der",type:"spki"});
    process.stdout.write(spki.subarray(-32).toString("base64"));
  ' 2>/dev/null || true)"
  key_source="key file ${VIBES_ED_KEY_FILE}"
else
  # Read the public key from the keychain copy via Sparkle's generate_keys.
  gk=""
  if [[ -n "${SPARKLE_BIN:-}" && -x "${SPARKLE_BIN}/generate_keys" ]]; then
    gk="${SPARKLE_BIN}/generate_keys"
  elif command -v generate_keys >/dev/null 2>&1; then
    gk="$(command -v generate_keys)"
  else
    gk="$(find "${HOME}/Library/Developer/Xcode/DerivedData" -type f -name generate_keys -path '*artifacts*' 2>/dev/null | head -1)"
  fi
  [[ -n "${gk}" ]] || die "cannot locate Sparkle's generate_keys to read the EdDSA public key. Build the app once (resolves the SwiftPM artifact), set SPARKLE_BIN, or set VIBES_ED_KEY_FILE."
  derived_pub="$("${gk}" -p 2>/dev/null || true)"
  key_source="keychain (generate_keys -p)"
fi

[[ -n "${derived_pub}" ]] || die "could not determine the EdDSA public key from ${key_source}. If using the keychain, import the key first: generate_keys -f <exported-key-file>"
if [[ "${derived_pub}" != "${expected_pub}" ]]; then
  die "EdDSA signing key does NOT match the app's SUPublicEDKey — signing with it would ship an update every installed app rejects.
  app SUPublicEDKey: ${expected_pub}
  ${key_source}:     ${derived_pub}
Use the original key whose public half is ${expected_pub}. If lost, you cannot ship verifiable updates to existing users."
fi
ok "EdDSA key matches SUPublicEDKey (${key_source})"

note "Preflight passed — safe to build and publish ${VIBES_RELEASE_VERSION} (build ${VIBES_BUILD_NUMBER})."
