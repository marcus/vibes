#!/usr/bin/env bash
set -euo pipefail

# Publish the signed/notarized Mac release artifacts created by
# scripts/release-mac.sh and scripts/generate-appcast.sh to the relay VPS.
#
# This script does not build, sign, or notarize. It only validates and uploads
# the already-staged DMG, Sparkle update zip, appcast, checksums, and latest
# manifest into ${DEPLOY_PATH}/releases.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "${SCRIPT_DIR}")"
cd "${REPO_ROOT}"

load_env_file() {
  local file="$1"
  if [[ -f "${file}" ]]; then
    set -a
    # shellcheck source=/dev/null
    source "${file}"
    set +a
  fi
}

load_env_file "${DEPLOY_ENV_FILE:-.env.deploy}"
load_env_file "${RELEASE_ENV_FILE:-.env.release}"

die() { echo "error: $*" >&2; exit 2; }
note() { echo "==> $*"; }
warn() { echo "warning: $*" >&2; }

APP_NAME="Vibes"
DEPLOY_USER="${DEPLOY_USER:-root}"
MINIMUM_MACOS="${VIBES_MINIMUM_MACOS:-14.0}"

required_vars=(
  DEPLOY_USER
  DEPLOY_HOST
  DEPLOY_PATH
  DEPLOY_DOMAIN
  VIBES_RELEASE_VERSION
  VIBES_BUILD_NUMBER
)

missing=()
for var in "${required_vars[@]}"; do
  [[ -n "${!var:-}" ]] || missing+=("${var}")
done
if (( ${#missing[@]} > 0 )); then
  echo "error: missing required environment variables:" >&2
  printf '  - %s\n' "${missing[@]}" >&2
  echo "Load them from .env.deploy/.env.release, set DEPLOY_ENV_FILE/RELEASE_ENV_FILE, or export them." >&2
  exit 2
fi

[[ "${VIBES_BUILD_DMG:-0}" == "1" ]] || die "VIBES_BUILD_DMG=1 is required; publish-mac-release.sh must not publish a zip-only first-download release"
[[ "${VIBES_BUILD_NUMBER}" =~ ^[1-9][0-9]*$ ]] || die "VIBES_BUILD_NUMBER must be a positive integer without leading zeros"

VERSION="${VIBES_RELEASE_VERSION}"
BUILD_NUMBER="${VIBES_BUILD_NUMBER}"
DOWNLOAD_BASE_URL="https://${DEPLOY_DOMAIN}/downloads"
HOSTED_ZIP_URL="${DOWNLOAD_BASE_URL}/${APP_NAME}-${VERSION}.zip"

APPCAST_XML="release/appcast/appcast.xml"
ZIP_PATH="release/appcast/${APP_NAME}-${VERSION}.zip"
DMG_PATH="build/${APP_NAME}-${VERSION}.dmg"
SHA256_PATH="build/SHA256SUMS"
LATEST_JSON_PATH="build/latest.json"

[[ -f "${APPCAST_XML}" ]] || die "missing ${APPCAST_XML}; run scripts/generate-appcast.sh first"
[[ -f "${ZIP_PATH}" ]] || die "missing ${ZIP_PATH}; run scripts/release-mac.sh first"
[[ -f "${DMG_PATH}" ]] || die "missing ${DMG_PATH}; set VIBES_BUILD_DMG=1 and rerun scripts/release-mac.sh"

note "Validating ${APP_NAME} ${VERSION} artifacts"
grep -Fq "${APP_NAME}-${VERSION}.zip" "${APPCAST_XML}" \
  || die "${APPCAST_XML} does not reference ${APP_NAME}-${VERSION}.zip"
grep -Fq "${DOWNLOAD_BASE_URL}/" "${APPCAST_XML}" \
  || die "${APPCAST_XML} does not use expected download base ${DOWNLOAD_BASE_URL}/"
grep -Fq "${HOSTED_ZIP_URL}" "${APPCAST_XML}" \
  || die "${APPCAST_XML} does not reference hosted zip URL ${HOSTED_ZIP_URL}"

if ! grep -Eq "(<sparkle:version>${BUILD_NUMBER}</sparkle:version>|sparkle:version=\"${BUILD_NUMBER}\")" "${APPCAST_XML}"; then
  die "${APPCAST_XML} does not contain Sparkle build number ${BUILD_NUMBER} as <sparkle:version> or sparkle:version=\"...\""
fi

file_mtime_epoch() {
  local file="$1"
  case "$(uname -s)" in
    Darwin|FreeBSD|OpenBSD|NetBSD) stat -f %m "${file}" ;;
    *) stat -c %Y "${file}" ;;
  esac
}

warn_if_older_than_latest_source_commit() {
  local latest_commit_epoch
  latest_commit_epoch="$(git log -1 --format=%ct -- client/ "release/release-notes/${VERSION}.md" 2>/dev/null || true)"
  [[ -n "${latest_commit_epoch}" ]] || return 0

  local file file_epoch
  for file in "${DMG_PATH}" "${ZIP_PATH}"; do
    file_epoch="$(file_mtime_epoch "${file}")"
    if (( file_epoch < latest_commit_epoch )); then
      warn "${file} is older than the latest git commit touching client/ or release/release-notes/${VERSION}.md; confirm you rebuilt from current sources"
    fi
  done
}

warn_if_older_than_latest_source_commit

note "Writing ${SHA256_PATH}"
{
  shasum -a 256 "${DMG_PATH}" | awk -v name="$(basename "${DMG_PATH}")" '{ print $1 "  " name }'
  shasum -a 256 "${ZIP_PATH}" | awk -v name="$(basename "${ZIP_PATH}")" '{ print $1 "  " name }'
} > "${SHA256_PATH}"

published_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
note "Writing ${LATEST_JSON_PATH}"
cat > "${LATEST_JSON_PATH}" <<EOF
{
  "version": "${VERSION}",
  "build": ${BUILD_NUMBER},
  "buildString": "${BUILD_NUMBER}",
  "minimumMacOS": "${MINIMUM_MACOS}",
  "dmg": "/downloads/${APP_NAME}.dmg",
  "stableDmg": "/downloads/${APP_NAME}.dmg",
  "versionedDmg": "/downloads/${APP_NAME}-${VERSION}.dmg",
  "zip": "/downloads/${APP_NAME}-${VERSION}.zip",
  "versionedZip": "/downloads/${APP_NAME}-${VERSION}.zip",
  "appcast": "/appcast.xml",
  "sha256": "/downloads/SHA256SUMS",
  "publishedAt": "${published_at}"
}
EOF

timestamp="$(date -u '+%Y%m%d%H%M%S')"
REMOTE_INCOMING_DIR="${DEPLOY_PATH}/releases/.incoming/${APP_NAME}-${VERSION}-${timestamp}"
REMOTE_TARGET="${DEPLOY_USER}@${DEPLOY_HOST}"

note "Creating remote incoming directory ${REMOTE_INCOMING_DIR}"
ssh "${REMOTE_TARGET}" "mkdir -p '${REMOTE_INCOMING_DIR}'"

note "Uploading release files to ${REMOTE_TARGET}:${REMOTE_INCOMING_DIR}/"
rsync -az --chmod=Fu=rw,Fgo=r \
  "${DMG_PATH}" \
  "${ZIP_PATH}" \
  "${APPCAST_XML}" \
  "${SHA256_PATH}" \
  "${LATEST_JSON_PATH}" \
  "${REMOTE_TARGET}:${REMOTE_INCOMING_DIR}/"

note "Installing release files on ${DEPLOY_HOST}"
ssh "${REMOTE_TARGET}" bash -s -- "${DEPLOY_PATH}" "${VERSION}" "${REMOTE_INCOMING_DIR}" <<'REMOTE_SCRIPT'
set -euo pipefail

deploy_path="$1"
version="$2"
incoming_dir="$3"
app_name="Vibes"
releases_dir="${deploy_path}/releases"
downloads_dir="${releases_dir}/downloads"

mkdir -p "${downloads_dir}"

install_immutable_artifact() {
  local source="$1"
  local destination="$2"
  if [[ -e "${destination}" ]]; then
    if cmp -s "${source}" "${destination}"; then
      return 0
    fi
    echo "error: refusing to overwrite immutable release artifact ${destination}; bump the version or remove the remote file explicitly" >&2
    exit 2
  fi
  install -m 0644 "${source}" "${destination}"
}

install_immutable_artifact "${incoming_dir}/${app_name}-${version}.dmg" "${downloads_dir}/${app_name}-${version}.dmg"
install_immutable_artifact "${incoming_dir}/${app_name}-${version}.zip" "${downloads_dir}/${app_name}-${version}.zip"
install -m 0644 "${incoming_dir}/SHA256SUMS" "${downloads_dir}/SHA256SUMS"

mv_test_src="${downloads_dir}/.${app_name}.mv-test-src.$$"
mv_test_dst="${downloads_dir}/.${app_name}.mv-test-dst.$$"
if [[ "$(uname -s)" == "Linux" ]] && : > "${mv_test_src}" && mv -T "${mv_test_src}" "${mv_test_dst}" 2>/dev/null; then
  rm -f "${mv_test_dst}"
  ln -sfn "${app_name}-${version}.dmg" "${downloads_dir}/${app_name}.dmg.tmp"
  mv -Tf "${downloads_dir}/${app_name}.dmg.tmp" "${downloads_dir}/${app_name}.dmg"
else
  rm -f "${mv_test_src}" "${mv_test_dst}"
  cp "${downloads_dir}/${app_name}-${version}.dmg" "${downloads_dir}/${app_name}.dmg.tmp"
  mv -f "${downloads_dir}/${app_name}.dmg.tmp" "${downloads_dir}/${app_name}.dmg"
fi

install -m 0644 "${incoming_dir}/latest.json" "${downloads_dir}/latest.json"
install -m 0644 "${incoming_dir}/appcast.xml" "${releases_dir}/appcast.xml"

rm -rf "${incoming_dir}"
REMOTE_SCRIPT

APPCAST_URL="https://${DEPLOY_DOMAIN}/appcast.xml"
VERSIONED_ZIP_URL="https://${DEPLOY_DOMAIN}/downloads/${APP_NAME}-${VERSION}.zip"
VERSIONED_DMG_URL="https://${DEPLOY_DOMAIN}/downloads/${APP_NAME}-${VERSION}.dmg"
LATEST_DMG_URL="https://${DEPLOY_DOMAIN}/downloads/${APP_NAME}.dmg"
SHA256_URL="https://${DEPLOY_DOMAIN}/downloads/SHA256SUMS"
LATEST_JSON_URL="https://${DEPLOY_DOMAIN}/downloads/latest.json"

header_has() {
  local headers="$1"
  local pattern="$2"
  printf '%s\n' "${headers}" | tr -d '\r' | grep -Eiq "${pattern}"
}

note "Smoke-checking public URLs"
public_urls=(
  "${APPCAST_URL}"
  "${VERSIONED_ZIP_URL}"
  "${VERSIONED_DMG_URL}"
  "${LATEST_DMG_URL}"
  "${SHA256_URL}"
  "${LATEST_JSON_URL}"
)
for url in "${public_urls[@]}"; do
  headers="$(curl -fsSI "${url}")"
  if [[ "${url}" == "${APPCAST_URL}" ]]; then
    header_has "${headers}" '^Cache-Control:[[:space:]]*.*no-cache' \
      || die "${APPCAST_URL} did not return a no-cache Cache-Control header"
  fi
  if [[ "${url}" == "${VERSIONED_DMG_URL}" || "${url}" == "${LATEST_DMG_URL}" ]]; then
    header_has "${headers}" '^Content-Type:[[:space:]]*(application/x-apple-diskimage|application/octet-stream|application/x-diskcopy)' \
      || die "${url} did not return a plausible disk image Content-Type"
  fi
  note "OK ${url}"
done

note "Verifying public appcast references hosted zip"
curl -fsS "${APPCAST_URL}" | grep -F "${HOSTED_ZIP_URL}" >/dev/null

cat <<EOF

Mac release published.

  Appcast:       https://${DEPLOY_DOMAIN}/appcast.xml
  Latest DMG:    https://${DEPLOY_DOMAIN}/downloads/${APP_NAME}.dmg
  Versioned DMG: https://${DEPLOY_DOMAIN}/downloads/${APP_NAME}-${VERSION}.dmg
  Update zip:    ${HOSTED_ZIP_URL}
  Checksums:     https://${DEPLOY_DOMAIN}/downloads/SHA256SUMS
  Manifest:      https://${DEPLOY_DOMAIN}/downloads/latest.json
EOF
