#!/usr/bin/env bash
set -euo pipefail

# Close out a published release: commit the regenerated appcast, tag the exact
# commit that shipped, and push both.
#
# Run this AFTER `make mac-release` has succeeded. Until it runs, the release
# exists on the server but not in git history: `generate_appcast` rewrites
# release/appcast/appcast.xml during publish, and nothing tags what shipped.
# Without a tag there is no way to check out the source of a released build —
# the first thing you want when a user reports a bug in a specific version.
#
# Usage:
#   scripts/finish-release.sh              # commit + tag + push
#   scripts/finish-release.sh --no-push    # commit + tag locally only
#   make mac-finish

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "${SCRIPT_DIR}")"
cd "${REPO_ROOT}"

die()  { echo "finish error: $*" >&2; exit 2; }
note() { echo "==> $*"; }
ok()   { echo "  ✓ $*"; }

PUSH=1
[[ "${1:-}" == "--no-push" ]] && PUSH=0

ENV_FILE="${RELEASE_ENV_FILE:-.env.release}"
if [[ -f "${ENV_FILE}" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "${ENV_FILE}"
  set +a
fi

VERSION="${VIBES_RELEASE_VERSION:-}"
BUILD="${VIBES_BUILD_NUMBER:-}"
[[ -n "${VERSION}" ]] || die "VIBES_RELEASE_VERSION is not set (need ${ENV_FILE})"
[[ -n "${BUILD}" ]] || die "VIBES_BUILD_NUMBER is not set (need ${ENV_FILE})"

TAG="v${VERSION}"
APPCAST="release/appcast/appcast.xml"

note "Finishing Vibes ${VERSION} (build ${BUILD})"

# --- The release must actually be live --------------------------------------
# Tagging a release that was never published, or was published at a different
# build, would put a lie in the history that is hard to detect later.
if [[ -n "${DEPLOY_DOMAIN:-}" ]] || [[ -f .env.deploy ]]; then
  if [[ -z "${DEPLOY_DOMAIN:-}" ]]; then
    set -a; # shellcheck source=/dev/null
    source .env.deploy; set +a
  fi
fi
if [[ -n "${DEPLOY_DOMAIN:-}" ]]; then
  if live="$(curl -fsS --max-time 15 "https://${DEPLOY_DOMAIN}/appcast.xml" 2>/dev/null)"; then
    grep -qF "<sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>" <<<"${live}" \
      || die "the live appcast does not list ${VERSION} — publish first (make mac-release), then finish."
    ok "live appcast lists ${VERSION}"
  else
    echo "  ! could not reach the live appcast; tagging on local state alone" >&2
  fi
fi

[[ -f "${APPCAST}" ]] || die "missing ${APPCAST}"
grep -qF "<sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>" "${APPCAST}" \
  || die "${APPCAST} does not list ${VERSION}; run make mac-release first"

# --- Commit the appcast, if publish changed it ------------------------------
if [[ -n "$(git status --porcelain -- "${APPCAST}")" ]]; then
  git add "${APPCAST}"
  git commit -q -m "chore(release): update appcast for ${VERSION}"
  ok "committed ${APPCAST}"
else
  ok "${APPCAST} already committed"
fi

# --- Refuse to tag a tree that does not match what shipped ------------------
dirty="$(git status --porcelain -- client/ release/ 2>/dev/null || true)"
if [[ -n "${dirty}" ]]; then
  echo "uncommitted changes under client/ or release/:" >&2
  printf '%s\n' "${dirty}" | sed 's/^/    /' >&2
  die "commit or stash them before tagging — the tag must describe the shipped binary"
fi

# --- Tag --------------------------------------------------------------------
if existing="$(git rev-parse -q --verify "refs/tags/${TAG}" 2>/dev/null)"; then
  head_sha="$(git rev-parse HEAD)"
  tagged_sha="$(git rev-parse "${TAG}^{commit}")"
  [[ "${tagged_sha}" == "${head_sha}" ]] \
    || die "tag ${TAG} already exists at ${tagged_sha:0:8}, but HEAD is ${head_sha:0:8}.
Released versions are immutable — do not move the tag; release a new version."
  ok "tag ${TAG} already at HEAD"
else
  git tag -a "${TAG}" -m "Vibes ${VERSION} (build ${BUILD})"
  ok "tagged ${TAG}"
fi

# --- Push -------------------------------------------------------------------
if (( PUSH )); then
  branch="$(git rev-parse --abbrev-ref HEAD)"
  git push origin "${branch}"
  git push origin "${TAG}"
  ok "pushed ${branch} and ${TAG}"
else
  note "--no-push: commit and tag are local. Push with:
  git push origin \$(git rev-parse --abbrev-ref HEAD) && git push origin ${TAG}"
fi

echo
note "Vibes ${VERSION} (build ${BUILD}) finished."
