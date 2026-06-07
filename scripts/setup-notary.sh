#!/usr/bin/env bash
set -euo pipefail

# One-time helper to store notarytool credentials in the Keychain as a named
# profile that release-mac.sh can reuse via --keychain-profile.
#
# Two credential styles are supported. App Store Connect API key is preferred
# (no password in your shell history, revocable, team-scoped).
#
#   App Store Connect API key (recommended):
#     scripts/setup-notary.sh api <profile-name> <key-id> <issuer-id> <path-to-AuthKey_XXXX.p8>
#
#   App-specific password (simpler, tied to your Apple ID):
#     scripts/setup-notary.sh password <profile-name> <apple-id> <team-id>
#     (you will be prompted for the app-specific password; create one at
#      https://account.apple.com > Sign-In and Security > App-Specific Passwords)
#
# The profile name you choose here is what you put in VIBES_NOTARY_PROFILE.

die() { echo "error: $*" >&2; exit 2; }

mode="${1:-}"
case "${mode}" in
  api)
    profile="${2:?profile name}"; key_id="${3:?key id}"; issuer="${4:?issuer id}"; key_path="${5:?path to .p8}"
    [[ -f "${key_path}" ]] || die "key file not found: ${key_path}"
    xcrun notarytool store-credentials "${profile}" \
      --key "${key_path}" --key-id "${key_id}" --issuer "${issuer}"
    ;;
  password)
    profile="${2:?profile name}"; apple_id="${3:?apple id}"; team_id="${4:?team id}"
    xcrun notarytool store-credentials "${profile}" \
      --apple-id "${apple_id}" --team-id "${team_id}"
    ;;
  *)
    die "usage: setup-notary.sh api <profile> <key-id> <issuer-id> <p8-path>
       setup-notary.sh password <profile> <apple-id> <team-id>"
    ;;
esac

echo "Stored notarytool profile. Set VIBES_NOTARY_PROFILE=${2} in .env.release."
