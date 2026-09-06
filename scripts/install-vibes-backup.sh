#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "${SCRIPT_DIR}")"
INSTALL_DIR="${HOME}/Library/Application Support/Vibes Backup"
KEY_DIR="${HOME}/.config/vibes-backup"
KEY_FILE="${KEY_DIR}/identity.txt"
PLIST="${HOME}/Library/LaunchAgents/com.opentangle.vibes-backup.plist"
LABEL="com.opentangle.vibes-backup"
VOLUME="/Volumes/Albatross"
BACKUP_DIR="${VOLUME}/backups/vibes"

mount | grep -Fq " on ${VOLUME} " || { echo "Backup volume is not mounted: ${VOLUME}" >&2; exit 1; }

mkdir -p "${INSTALL_DIR}" "${KEY_DIR}" "${HOME}/Library/LaunchAgents"
chmod 700 "${INSTALL_DIR}" "${KEY_DIR}"
mkdir -p "${BACKUP_DIR}"
chmod 700 "${BACKUP_DIR}"
[[ -e "${BACKUP_DIR}/.vibes-db-backups" ]] || : > "${BACKUP_DIR}/.vibes-db-backups"
if [[ ! -f "${KEY_FILE}" ]]; then
  age-keygen -o "${KEY_FILE}" >/dev/null 2>&1
fi
chmod 600 "${KEY_FILE}"
install -m 700 "${REPO_ROOT}/scripts/backup-vibes-db.sh" "${INSTALL_DIR}/backup-vibes-db"

sed "s|\${BACKUP_SCRIPT}|${INSTALL_DIR}/backup-vibes-db|g" \
  "${REPO_ROOT}/deploy/com.opentangle.vibes-backup.plist.template" > "${PLIST}.tmp"
plutil -lint "${PLIST}.tmp" >/dev/null
mv "${PLIST}.tmp" "${PLIST}"
chmod 600 "${PLIST}"

launchctl bootout "gui/$(id -u)/${LABEL}" 2>/dev/null || true
if [[ "${1:-}" == "--activate" ]]; then
  launchctl bootstrap "gui/$(id -u)" "${PLIST}"
  echo "Installed and activated nightly Vibes database backup at 03:17 local time."
else
  echo "Installed Vibes database backup inactive. Run this installer with --activate after granting background removable-volume access."
fi
