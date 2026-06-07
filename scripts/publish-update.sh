#!/usr/bin/env bash
set -euo pipefail

# Publish the staged Sparkle appcast + update archives to the relay host, where
# nginx serves them (see deploy/nginx.conf.template). Run after
# scripts/release-mac.sh and scripts/generate-appcast.sh.
#
# Reuses the relay's deploy target (.env.deploy) for host/path. The appcast
# lands at ${DEPLOY_PATH}/releases/appcast.xml and archives under
# ${DEPLOY_PATH}/releases/downloads/ — matching deploy/nginx.conf.template and
# outside the rsync'd server/ tree, so a `make deploy` never disturbs them.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "${SCRIPT_DIR}")"
cd "${REPO_ROOT}"

ENV_FILE="${DEPLOY_ENV_FILE:-.env.deploy}"
if [[ -f "${ENV_FILE}" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "${ENV_FILE}"
  set +a
fi

die() { echo "error: $*" >&2; exit 2; }
note() { echo "==> $*"; }

DEPLOY_USER="${DEPLOY_USER:-root}"
DEPLOY_HOST="${DEPLOY_HOST:-}"
DEPLOY_DOMAIN="${DEPLOY_DOMAIN:-}"
DEPLOY_PATH="${DEPLOY_PATH:-/var/www/${APP_NAME:-vibes}}"
RELEASES_DIR="${DEPLOY_PATH}/releases"
DOWNLOADS_DIR="${RELEASES_DIR}/downloads"
STAGING="release/appcast"

[[ -n "${DEPLOY_HOST}" ]] || die "DEPLOY_HOST is required (set it in .env.deploy)"
[[ -f "${STAGING}/appcast.xml" ]] || die "no ${STAGING}/appcast.xml; run scripts/generate-appcast.sh first"

note "Publishing to ${DEPLOY_USER}@${DEPLOY_HOST}:${RELEASES_DIR}"
ssh "${DEPLOY_USER}@${DEPLOY_HOST}" "mkdir -p '${DOWNLOADS_DIR}'"

# Ship the update archives first, then the appcast last, so the feed never
# references an archive that has not finished uploading.
shopt -s nullglob
archives=("${STAGING}"/*.zip "${STAGING}"/*.dmg "${STAGING}"/*.delta)
shopt -u nullglob
if (( ${#archives[@]} > 0 )); then
  note "Uploading ${#archives[@]} archive(s) to downloads/..."
  rsync -az --chmod=Fu=rw,Fgo=r "${archives[@]}" "${DEPLOY_USER}@${DEPLOY_HOST}:${DOWNLOADS_DIR}/"
else
  note "No new archives staged; updating appcast only."
fi

note "Uploading appcast.xml..."
rsync -az --chmod=Fu=rw,Fgo=r "${STAGING}/appcast.xml" "${DEPLOY_USER}@${DEPLOY_HOST}:${RELEASES_DIR}/"

# Verify the feed is reachable over HTTPS.
if [[ -n "${DEPLOY_DOMAIN}" ]]; then
  note "Verifying https://${DEPLOY_DOMAIN}/appcast.xml ..."
  code="$(curl -sS -o /dev/null -w '%{http_code}' "https://${DEPLOY_DOMAIN}/appcast.xml" || true)"
  [[ "${code}" == "200" ]] || die "appcast not reachable: HTTP ${code}. Is the nginx update channel deployed?"
  note "Appcast live: https://${DEPLOY_DOMAIN}/appcast.xml (HTTP 200)"
fi

echo "Publish complete."
