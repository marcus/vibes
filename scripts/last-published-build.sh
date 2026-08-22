#!/usr/bin/env bash
set -euo pipefail

# Print the highest Sparkle build number that has already been published.
#
# Sparkle decides whether to offer an update by comparing <sparkle:version>
# (the build number), NOT the marketing version. A release whose build number
# does not exceed the last published one publishes perfectly green and is then
# offered to nobody — the failure is invisible until a user reports it. This
# script is the oracle both scripts/preflight-release.sh (to refuse such a
# release) and scripts/bump-version.sh (to pick the next build) consult.
#
# Sources, highest wins:
#   1. release/appcast/appcast.xml — the committed feed, always available.
#   2. The live feed at ${DEPLOY_DOMAIN}/appcast.xml — authoritative, and the
#      one that catches a local checkout that is behind the server.
#
# Prints 0 when nothing has been published yet (first release).
#
# Usage:
#   scripts/last-published-build.sh              # highest build, local + live
#   VIBES_SKIP_REMOTE_APPCAST=1 scripts/last-published-build.sh   # local only
#   scripts/last-published-build.sh --verbose    # report each source on stderr

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "${SCRIPT_DIR}")"
cd "${REPO_ROOT}"

VERBOSE=0
[[ "${1:-}" == "--verbose" ]] && VERBOSE=1

load_env_file() {
  if [[ -f "$1" ]]; then
    set -a
    # shellcheck source=/dev/null
    source "$1"
    set +a
  fi
}
load_env_file "${DEPLOY_ENV_FILE:-.env.deploy}"
load_env_file "${RELEASE_ENV_FILE:-.env.release}"

# Extract build numbers from an appcast on stdin.
#
# Only <sparkle:version>N</sparkle:version> elements and sparkle:version="N"
# attributes count. Delta enclosures carry sparkle:deltaFrom="N", which names a
# build the delta patches FROM, not a published item — matching it would be
# harmless here (it is always <= a real item) but the intent matters if the feed
# shape changes.
extract_builds() {
  grep -oE '<sparkle:version>[0-9]+</sparkle:version>|sparkle:version="[0-9]+"' \
    | grep -oE '[0-9]+' || true
}

max_of() {
  local max=0 n
  while read -r n; do
    [[ -n "${n}" ]] || continue
    (( n > max )) && max="${n}"
  done
  printf '%s\n' "${max}"
}

report() { (( VERBOSE )) && echo "  $*" >&2 || true; }

overall=0

LOCAL_APPCAST="release/appcast/appcast.xml"
if [[ -f "${LOCAL_APPCAST}" ]]; then
  local_max="$(extract_builds < "${LOCAL_APPCAST}" | max_of)"
  report "local  ${LOCAL_APPCAST}: ${local_max}"
  (( local_max > overall )) && overall="${local_max}"
else
  report "local  ${LOCAL_APPCAST}: (absent)"
fi

if [[ "${VIBES_SKIP_REMOTE_APPCAST:-0}" != "1" && -n "${DEPLOY_DOMAIN:-}" ]]; then
  live_url="https://${DEPLOY_DOMAIN}/appcast.xml"
  if live_xml="$(curl -fsS --max-time 15 "${live_url}" 2>/dev/null)"; then
    live_max="$(extract_builds <<<"${live_xml}" | max_of)"
    report "live   ${live_url}: ${live_max}"
    (( live_max > overall )) && overall="${live_max}"
  else
    # Unreachable live feed must not block a release; the local feed still
    # provides a floor. Callers that need certainty check the exit note.
    report "live   ${live_url}: (unreachable — using local only)"
  fi
fi

printf '%s\n' "${overall}"
