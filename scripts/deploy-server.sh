#!/usr/bin/env bash
set -euo pipefail

DEPLOY_USER="${DEPLOY_USER:-root}"
DEPLOY_HOST="${DEPLOY_HOST:-146.190.117.215}"
DEPLOY_PATH="${DEPLOY_PATH:-/var/www/vibes}"
DEPLOY_URL="${DEPLOY_URL:-https://vibes.opentangle.com/healthz}"
SERVICE_NAME="${SERVICE_NAME:-vibes}"
DRY_RUN="${DRY_RUN:-0}"

RSYNC_FLAGS=(-az --delete --chmod=Du=rwx,Dgo=rx,Fu=rw,Fgo=r)
if [[ "${DRY_RUN}" == "1" ]]; then
  RSYNC_FLAGS+=(--dry-run)
fi

echo "Checking relay syntax..."
(cd server && npm run check)

echo "Preparing ${DEPLOY_USER}@${DEPLOY_HOST}:${DEPLOY_PATH}..."
ssh "${DEPLOY_USER}@${DEPLOY_HOST}" "mkdir -p '${DEPLOY_PATH}/server' '${DEPLOY_PATH}/data'"

echo "Uploading relay..."
rsync "${RSYNC_FLAGS[@]}" server/ "${DEPLOY_USER}@${DEPLOY_HOST}:${DEPLOY_PATH}/server/"

if [[ "${DRY_RUN}" == "1" ]]; then
  echo "Dry run complete; skipped service restart and smoke check."
  exit 0
fi

echo "Restarting ${SERVICE_NAME}.service..."
ssh "${DEPLOY_USER}@${DEPLOY_HOST}" "systemctl restart '${SERVICE_NAME}.service'"

echo "Checking ${DEPLOY_URL}..."
SMOKE_FILE="$(mktemp -t vibes-deploy-smoke.XXXXXX)"
STATUS=""
for attempt in {1..12}; do
  STATUS="$(curl -sS -o "${SMOKE_FILE}" -w "%{http_code}" "${DEPLOY_URL}" || true)"
  if [[ "${STATUS}" == "200" ]]; then
    break
  fi
  echo "Smoke check attempt ${attempt} returned ${STATUS:-curl-error}; retrying..."
  sleep 2
done

if [[ "${STATUS}" != "200" ]]; then
  echo "Deploy smoke check failed: ${DEPLOY_URL} returned HTTP ${STATUS}" >&2
  cat "${SMOKE_FILE}" >&2 || true
  exit 1
fi

node -e "const fs=require('fs'); const body=JSON.parse(fs.readFileSync(process.argv[1], 'utf8')); if (!body.ok) process.exit(1)" "${SMOKE_FILE}"

echo "Deployment complete: ${DEPLOY_URL}"
