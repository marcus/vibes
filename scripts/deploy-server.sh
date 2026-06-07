#!/usr/bin/env bash
set -euo pipefail

# Anchor to the repo root so relative paths work regardless of the caller's CWD.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$(dirname "${SCRIPT_DIR}")"

ENV_FILE="${DEPLOY_ENV_FILE:-.env.deploy}"
if [[ -f "${ENV_FILE}" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "${ENV_FILE}"
  set +a
fi

APP_NAME="${APP_NAME:-vibes}"
DEPLOY_USER="${DEPLOY_USER:-root}"
DEPLOY_HOST="${DEPLOY_HOST:-}"
DEPLOY_DOMAIN="${DEPLOY_DOMAIN:-}"
DEPLOY_PATH="${DEPLOY_PATH:-/var/www/${APP_NAME}}"
SERVICE_NAME="${SERVICE_NAME:-${APP_NAME}}"
SERVICE_HOST="${SERVICE_HOST:-127.0.0.1}"
SERVICE_PORT="${SERVICE_PORT:-3136}"
DEPLOY_URL="${DEPLOY_URL:-}"
DEPLOY_RESOLVE_IP="${DEPLOY_RESOLVE_IP:-}"
DRY_RUN="${DRY_RUN:-0}"

if [[ -z "${DEPLOY_HOST}" ]]; then
  echo "DEPLOY_HOST is required. Copy .env.deploy.example to .env.deploy and set your server host." >&2
  exit 2
fi

if [[ -z "${DEPLOY_URL}" ]]; then
  if [[ -n "${DEPLOY_DOMAIN}" ]]; then
    DEPLOY_URL="https://${DEPLOY_DOMAIN}/healthz"
  else
    DEPLOY_URL="http://${DEPLOY_HOST}:${SERVICE_PORT}/healthz"
  fi
fi

# Ship source only. node_modules, the SvelteKit build, and the live database
# stay on the host: dependencies are reinstalled and rebuilt there because
# better-sqlite3 is a native module that must match the server's architecture.
RSYNC_FLAGS=(
  -az --delete --chmod=Du=rwx,Dgo=rx,Fu=rw,Fgo=r
  --exclude=node_modules --exclude=build --exclude=.svelte-kit
  --exclude=data --exclude='.env' --exclude='.env.*'
)
if [[ "${DRY_RUN}" == "1" ]]; then
  RSYNC_FLAGS+=(--dry-run)
fi

echo "Running relay tests..."
(cd server && npm run check)

echo "Preparing ${DEPLOY_USER}@${DEPLOY_HOST}:${DEPLOY_PATH}..."
ssh "${DEPLOY_USER}@${DEPLOY_HOST}" "mkdir -p '${DEPLOY_PATH}/server' '${DEPLOY_PATH}/data' '${DEPLOY_PATH}/releases/downloads'"

echo "Uploading relay source..."
rsync "${RSYNC_FLAGS[@]}" server/ "${DEPLOY_USER}@${DEPLOY_HOST}:${DEPLOY_PATH}/server/"

if [[ "${DRY_RUN}" == "1" ]]; then
  echo "Dry run complete; skipped install, build, restart, and smoke check."
  exit 0
fi

echo "Installing dependencies and building on host..."
ssh "${DEPLOY_USER}@${DEPLOY_HOST}" "cd '${DEPLOY_PATH}/server' && npm ci && npm run build && npm prune --omit=dev" \
  || { echo "Host build failed; the running service was left untouched. Fix and redeploy." >&2; exit 1; }

echo "Restarting ${SERVICE_NAME}.service..."
ssh "${DEPLOY_USER}@${DEPLOY_HOST}" "systemctl restart '${SERVICE_NAME}.service'"

echo "Checking ${DEPLOY_URL}..."
SMOKE_FILE="$(mktemp -t vibes-deploy-smoke.XXXXXX)"
trap 'rm -f "${SMOKE_FILE}"' EXIT
STATUS=""
CURL_RESOLVE_ARGS=()
if [[ -z "${DEPLOY_RESOLVE_IP}" && "${DEPLOY_HOST}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  DEPLOY_RESOLVE_IP="${DEPLOY_HOST}"
fi

if [[ -n "${DEPLOY_RESOLVE_IP}" ]]; then
  DEPLOY_URL_HOST="$(node -e "const url = new URL(process.argv[1]); console.log(url.hostname)" "${DEPLOY_URL}")"
  DEPLOY_URL_PORT="$(node -e "const url = new URL(process.argv[1]); console.log(url.port || (url.protocol === 'https:' ? '443' : '80'))" "${DEPLOY_URL}")"
  CURL_RESOLVE_ARGS=(--resolve "${DEPLOY_URL_HOST}:${DEPLOY_URL_PORT}:${DEPLOY_RESOLVE_IP}")
fi

for attempt in {1..12}; do
  STATUS="$(curl "${CURL_RESOLVE_ARGS[@]}" -sS -o "${SMOKE_FILE}" -w "%{http_code}" "${DEPLOY_URL}" || true)"
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
