#!/usr/bin/env bash
set -euo pipefail

# Bump the release version everywhere it lives, in one step.
#
# The version is stored in four places across two files, and a partial bump
# fails in a different way at each site:
#   client/Vibes.xcodeproj/project.pbxproj
#     MARKETING_VERSION        (x2 — Debug and Release configurations)
#     CURRENT_PROJECT_VERSION  (x2 — same)
#   .env.release (gitignored)
#     VIBES_RELEASE_VERSION / VIBES_BUILD_NUMBER
#
# Miss the Release MARKETING_VERSION and preflight catches it. Miss
# CURRENT_PROJECT_VERSION and — before preflight check 2a existed — the release
# published green and reached nobody. Doing all four together removes the class.
#
# Usage:
#   scripts/bump-version.sh 0.12.0        # build = last published + 1
#   scripts/bump-version.sh 0.12.0 30     # explicit build number
#   make mac-bump VERSION=0.12.0
#
# Writes a release-notes stub if one does not exist yet (preflight requires the
# file; Sparkle shows it to every user in the update dialog, so it must be
# edited before releasing — the stub says so and preflight is not fooled by it).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "${SCRIPT_DIR}")"
cd "${REPO_ROOT}"

die()  { echo "bump error: $*" >&2; exit 2; }
note() { echo "==> $*"; }
ok()   { echo "  ✓ $*"; }

VERSION="${1:-}"
BUILD="${2:-}"

[[ -n "${VERSION}" ]] || die "usage: scripts/bump-version.sh <version> [build]
  e.g. scripts/bump-version.sh 0.12.0"

[[ "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
  || die "version must be MAJOR.MINOR.PATCH (got '${VERSION}')"

PBXPROJ="client/Vibes.xcodeproj/project.pbxproj"
ENV_FILE="${RELEASE_ENV_FILE:-.env.release}"
NOTES="release/release-notes/${VERSION}.md"

[[ -f "${PBXPROJ}" ]] || die "missing ${PBXPROJ}"
[[ -f "${ENV_FILE}" ]] || die "missing ${ENV_FILE} — copy .env.release.example to .env.release and fill it in"

note "Bumping Vibes to ${VERSION}"

# --- Build number -----------------------------------------------------------
last_build="$("${SCRIPT_DIR}/last-published-build.sh" 2>/dev/null || echo 0)"
[[ "${last_build}" =~ ^[0-9]+$ ]] || last_build=0

if [[ -z "${BUILD}" ]]; then
  BUILD=$(( last_build + 1 ))
  ok "build ${BUILD} (last published ${last_build})"
else
  [[ "${BUILD}" =~ ^[1-9][0-9]*$ ]] || die "build must be a positive integer (got '${BUILD}')"
  (( BUILD > last_build )) || die "build ${BUILD} does not exceed the last published build (${last_build}).
Sparkle compares build numbers — a release that does not advance it is offered to nobody."
  ok "build ${BUILD} (explicit; last published ${last_build})"
fi

# --- Refuse to reuse a shipped version --------------------------------------
LOCAL_APPCAST="release/appcast/appcast.xml"
if [[ -f "${LOCAL_APPCAST}" ]] && \
   grep -qF "<sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>" "${LOCAL_APPCAST}"; then
  die "version ${VERSION} has already been published (it appears in ${LOCAL_APPCAST}).
Published artifacts are immutable on the server; pick a new version."
fi

# --- project.pbxproj --------------------------------------------------------
# Every occurrence, both configurations. Counted afterwards so a project
# restructure that changes the number of configurations is noticed here rather
# than through a confusing preflight mismatch.
sed -i '' \
  -e "s/MARKETING_VERSION = [^;]*;/MARKETING_VERSION = ${VERSION};/g" \
  -e "s/CURRENT_PROJECT_VERSION = [^;]*;/CURRENT_PROJECT_VERSION = ${BUILD};/g" \
  "${PBXPROJ}"

mv_count="$(grep -c "MARKETING_VERSION = ${VERSION};" "${PBXPROJ}" || true)"
cpv_count="$(grep -c "CURRENT_PROJECT_VERSION = ${BUILD};" "${PBXPROJ}" || true)"
(( mv_count >= 1 )) || die "failed to set MARKETING_VERSION in ${PBXPROJ}"
(( cpv_count >= 1 )) || die "failed to set CURRENT_PROJECT_VERSION in ${PBXPROJ}"
ok "${PBXPROJ}: MARKETING_VERSION ×${mv_count}, CURRENT_PROJECT_VERSION ×${cpv_count}"

# --- .env.release -----------------------------------------------------------
sed -i '' \
  -e "s/^VIBES_RELEASE_VERSION=.*/VIBES_RELEASE_VERSION=\"${VERSION}\"/" \
  -e "s/^VIBES_BUILD_NUMBER=.*/VIBES_BUILD_NUMBER=\"${BUILD}\"/" \
  "${ENV_FILE}"

grep -q "^VIBES_RELEASE_VERSION=\"${VERSION}\"$" "${ENV_FILE}" \
  || die "failed to set VIBES_RELEASE_VERSION in ${ENV_FILE}"
grep -q "^VIBES_BUILD_NUMBER=\"${BUILD}\"$" "${ENV_FILE}" \
  || die "failed to set VIBES_BUILD_NUMBER in ${ENV_FILE}"
ok "${ENV_FILE}: VIBES_RELEASE_VERSION, VIBES_BUILD_NUMBER"

# --- Release notes ----------------------------------------------------------
if [[ -f "${NOTES}" ]]; then
  ok "${NOTES} already exists"
else
  mkdir -p "$(dirname "${NOTES}")"
  cat > "${NOTES}" <<EOF
# Vibes ${VERSION}

TODO: one plain sentence on what this release gives the user.

- TODO: user-facing change, described by what it does for them.

<!--
Sparkle renders this file as the release notes in the update dialog.
Keep it short, user-facing, and plain. Do not include internal repo paths,
branch names, commit messages, or tokens. One file per version.
-->
EOF
  ok "${NOTES} (stub — edit before releasing)"
fi

echo
note "Bumped to ${VERSION} (build ${BUILD})."
cat <<EOF

Next:
  1. \$EDITOR ${NOTES}
  2. git add ${PBXPROJ} ${NOTES} && git commit -m "chore: prepare Vibes ${VERSION} release"
  3. make mac-preflight     # verify without building
  4. make mac-release       # build, notarize, publish
  5. make mac-finish        # commit the appcast, tag v${VERSION}, push
EOF
