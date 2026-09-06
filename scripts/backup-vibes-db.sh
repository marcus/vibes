#!/usr/bin/env bash
set -euo pipefail

PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${HOME}/.local/share/mise/shims"

readonly VOLUME="${VIBES_BACKUP_VOLUME:-/Volumes/Albatross}"
readonly BACKUP_DIR="${VIBES_BACKUP_DIR:-${VOLUME}/backups/vibes}"
readonly IDENTITY_FILE="${VIBES_BACKUP_IDENTITY:-${HOME}/.config/vibes-backup/identity.txt}"
readonly REMOTE="${VIBES_BACKUP_REMOTE:-root@146.190.117.215}"
readonly REMOTE_DB="${VIBES_BACKUP_REMOTE_DB:-/var/www/vibes/data/vibes.sqlite}"
readonly RETAIN_DAYS="${VIBES_BACKUP_RETAIN_DAYS:-30}"
readonly LOG_FILE="${VIBES_BACKUP_LOG:-${HOME}/Library/Logs/VibesBackup/backup.log}"
readonly LOCK_DIR="${HOME}/Library/Caches/com.opentangle.vibes-backup.lock"

mkdir -p "$(dirname "${LOG_FILE}")"
if [[ -f "${LOG_FILE}" ]] && [[ $(stat -f %z "${LOG_FILE}") -gt 262144 ]]; then
  tail -n 200 "${LOG_FILE}" > "${LOG_FILE}.tmp"
  mv "${LOG_FILE}.tmp" "${LOG_FILE}"
fi
exec >>"${LOG_FILE}" 2>&1

timestamp() { date -u '+%Y-%m-%dT%H:%M:%SZ'; }
fail() { echo "$(timestamp) ERROR $*"; exit 1; }

if ! mkdir "${LOCK_DIR}" 2>/dev/null; then
  fail "another backup is already running"
fi
cleanup() {
  rm -rf "${LOCK_DIR}"
  [[ -z "${PARTIAL_FILE:-}" ]] || rm -f "${PARTIAL_FILE}"
  if [[ -n "${REMOTE_TMP:-}" ]] && [[ "${REMOTE_TMP}" =~ ^/tmp/vibes-db\.[A-Za-z0-9]+\.sqlite$ ]]; then
    gtimeout 30s ssh -o BatchMode=yes -o ConnectTimeout=15 "${REMOTE}" "rm -f '${REMOTE_TMP}'" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT INT TERM

mount | grep -Fq " on ${VOLUME} " || fail "backup volume is not mounted: ${VOLUME}"
[[ -f "${IDENTITY_FILE}" ]] || fail "age identity is missing: ${IDENTITY_FILE}"
[[ $(stat -f %Lp "${IDENTITY_FILE}") == "600" ]] || fail "age identity must have mode 0600"
command -v age >/dev/null || fail "age is not installed"
command -v age-keygen >/dev/null || fail "age-keygen is not installed"
command -v gtimeout >/dev/null || fail "gtimeout is not installed"
command -v shasum >/dev/null || fail "shasum is not installed"
command -v uuidgen >/dev/null || fail "uuidgen is not installed"

mkdir -p "${BACKUP_DIR}"
chmod 700 "${BACKUP_DIR}"
readonly MARKER="${BACKUP_DIR}/.vibes-db-backups"
[[ -e "${MARKER}" ]] || : > "${MARKER}"
[[ -f "${MARKER}" ]] || fail "backup directory ownership marker is missing"

readonly STAMP="$(date -u '+%Y%m%dT%H%M%SZ')"
readonly RUN_ID="$(uuidgen | tr '[:upper:]' '[:lower:]')"
readonly FINAL_FILE="${BACKUP_DIR}/vibes-db-${STAMP}-${RUN_ID}.sqlite.age"
PARTIAL_FILE="${FINAL_FILE}.partial.$$"
readonly RECIPIENT="$(age-keygen -y "${IDENTITY_FILE}")"

echo "$(timestamp) starting consistent SQLite backup"
REMOTE_META="$(gtimeout 2m ssh -o BatchMode=yes -o ConnectTimeout=15 "${REMOTE}" \
  "set -eu; tmp=\$(mktemp /tmp/vibes-db.XXXXXX.sqlite); sqlite3 '${REMOTE_DB}' \".timeout 10000\" \".backup '\$tmp'\"; test \"\$(sqlite3 \"\$tmp\" 'PRAGMA quick_check;')\" = ok; printf '%s %s\\n' \"\$tmp\" \"\$(sha256sum \"\$tmp\" | cut -d' ' -f1)\""
)"
read -r REMOTE_TMP EXPECTED_SHA <<<"${REMOTE_META}"
[[ "${REMOTE_TMP}" =~ ^/tmp/vibes-db\.[A-Za-z0-9]+\.sqlite$ ]] || fail "remote backup returned an invalid temporary path"
[[ "${EXPECTED_SHA}" =~ ^[a-f0-9]{64}$ ]] || fail "remote backup returned an invalid checksum"

gtimeout 10m ssh -o BatchMode=yes -o ConnectTimeout=15 "${REMOTE}" "cat '${REMOTE_TMP}'" \
  | age -r "${RECIPIENT}" -o "${PARTIAL_FILE}"
ACTUAL_SHA="$(age -d -i "${IDENTITY_FILE}" "${PARTIAL_FILE}" | shasum -a 256 | cut -d' ' -f1)"
[[ "${ACTUAL_SHA}" == "${EXPECTED_SHA}" ]] || fail "encrypted backup checksum verification failed"
mv "${PARTIAL_FILE}" "${FINAL_FILE}"
PARTIAL_FILE=""
gtimeout 30s ssh -o BatchMode=yes -o ConnectTimeout=15 "${REMOTE}" "rm -f '${REMOTE_TMP}'"
REMOTE_TMP=""

# Remove only completed files owned by this job, and only after a new verified
# backup has been atomically published.
find "${BACKUP_DIR}" -maxdepth 1 -type f -name 'vibes-db-????????T??????Z-????????-????-????-????-????????????.sqlite.age' -mtime "+$((RETAIN_DAYS - 1))" -delete

echo "$(timestamp) completed $(basename "${FINAL_FILE}") bytes=$(stat -f %z "${FINAL_FILE}") retention_days=${RETAIN_DAYS}"
