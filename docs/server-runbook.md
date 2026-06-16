# Server Runbook

The relay deploy target is configured through environment variables. Copy `.env.deploy.example` to `.env.deploy` and edit it for your host.

Required values:

- `DEPLOY_HOST`: SSH host or IP.
- `DEPLOY_DOMAIN`: public DNS name for the relay.

Common values:

- `DEPLOY_USER`: SSH user, usually `root`.
- `DEPLOY_PATH`: remote app directory.
- `SERVICE_NAME`: systemd service name.
- `SERVICE_HOST`: local bind address, usually `127.0.0.1`.
- `SERVICE_PORT`: local relay port.
- `DEPLOY_URL`: smoke-check URL. Defaults to `https://${DEPLOY_DOMAIN}/healthz`.

## Local Relay

The relay is a SvelteKit app (adapter-node) backed by SQLite via better-sqlite3.
Users have an optional account-level IANA timezone. New clients send the Mac
timezone at registration; existing accounts can remain `NULL` until import,
profile hydration, or the relay resolves a multi-device disagreement from
upgraded status rows. Feed responses intentionally do not expose timezones;
`GET /api/me` returns the authenticated user's own timezone for setup/config
hydration.

Development, with hot reload:

```bash
cd server && npm install
cd .. && make server-dev
curl http://127.0.0.1:5173/healthz
```

Production-style build and run (`node build`):

```bash
make server
```

adapter-node validates form posts against the `ORIGIN` environment variable, so
set `ORIGIN` (plus `HOST`/`PORT`) when running the build directly; the systemd
unit sets `ORIGIN` from `DEPLOY_DOMAIN`.

Seed a user and invite for local testing:

```bash
cd server
VIBES_DB_PATH=data/dev.sqlite node cli.mjs users create --handle marcus --display-name Marcus
VIBES_DB_PATH=data/dev.sqlite node cli.mjs invites create --user marcus
```

## Routine Deploy

```bash
make deploy
```

Useful overrides:

```bash
DEPLOY_HOST=203.0.113.10 DEPLOY_DOMAIN=vibes.example.com make deploy
DRY_RUN=1 make deploy
```

The deploy script reads `.env.deploy` automatically when present.

## First-Time Bootstrap

The host needs Node.js 20, 22, or 24 and npm. Node 26 is not currently supported
by the relay's SQLite native dependency. `make deploy` runs `npm ci && npm run
build` on the host, so better-sqlite3 is compiled there for the server's
architecture; its prebuilt binaries cover common Linux targets, otherwise
install `build-essential` and `python3`.

Load your deploy environment before running the bootstrap commands:

```bash
set -a
source .env.deploy
set +a
```

1. Create the DNS record for `DEPLOY_DOMAIN`.
2. Issue a certificate on the VPS:

```bash
ssh "$DEPLOY_USER@$DEPLOY_HOST" \
  "certbot certonly --dns-cloudflare --dns-cloudflare-credentials /root/.cloudflare-dns.ini --dns-cloudflare-propagation-seconds 60 -d $DEPLOY_DOMAIN"
```

3. Render nginx and systemd config:

```bash
node scripts/render-deploy-config.mjs
```

4. Install nginx and systemd units:

```bash
scp "deploy/rendered/${APP_NAME}.nginx.conf" "$DEPLOY_USER@$DEPLOY_HOST:/etc/nginx/sites-available/${DEPLOY_DOMAIN}"
scp "deploy/rendered/${SERVICE_NAME}.service" "$DEPLOY_USER@$DEPLOY_HOST:/etc/systemd/system/${SERVICE_NAME}.service"
ssh "$DEPLOY_USER@$DEPLOY_HOST" \
  "ln -sf /etc/nginx/sites-available/${DEPLOY_DOMAIN} /etc/nginx/sites-enabled/${DEPLOY_DOMAIN} && systemctl daemon-reload && systemctl enable ${SERVICE_NAME}.service && nginx -t && systemctl reload nginx"
```

5. Deploy:

```bash
make deploy
```

## Auto-Update Channel

The macOS app's Sparkle appcast and release downloads are served as static
files from the same host, decoupled from relay deploys:

- `https://${DEPLOY_DOMAIN}/download` → SvelteKit download page with the primary DMG link and checksum link.
- `https://${DEPLOY_DOMAIN}/downloads/Vibes.dmg` → `${DEPLOY_PATH}/releases/downloads/Vibes.dmg`; stable first-download URL, no-cache, atomically repointed each release.
- `https://${DEPLOY_DOMAIN}/downloads/Vibes-<version>.dmg` → `${DEPLOY_PATH}/releases/downloads/Vibes-<version>.dmg`; immutable first-download artifact.
- `https://${DEPLOY_DOMAIN}/downloads/Vibes-<version>.zip` → `${DEPLOY_PATH}/releases/downloads/Vibes-<version>.zip`; immutable Sparkle update archive.
- `https://${DEPLOY_DOMAIN}/appcast.xml` → `${DEPLOY_PATH}/releases/appcast.xml`; no-cache Sparkle feed.
- `https://${DEPLOY_DOMAIN}/downloads/latest.json` → `${DEPLOY_PATH}/releases/downloads/latest.json`; generated public manifest consumed by the download page.
- `https://${DEPLOY_DOMAIN}/downloads/SHA256SUMS` → `${DEPLOY_PATH}/releases/downloads/SHA256SUMS`; generated checksums for the current DMG and ZIP.

These `location` blocks live in [nginx.conf.template](file:///Users/marcusvorwaller/code/vibes/deploy/nginx.conf.template), so re-rendering and
reinstalling the nginx config (bootstrap steps 3–4) enables them. The
`${DEPLOY_PATH}/releases` directory sits outside the rsync'd `server/` tree, so
`make deploy` never touches published releases.

Publishing is part of the **client** release flow, not the relay deploy: after
building a signed/notarized app and generating the appcast, `make mac-release`
runs `scripts/publish-mac-release.sh`. That script loads `.env.deploy` and
`.env.release`, requires `DEPLOY_USER` explicitly, creates an incoming directory
under `${DEPLOY_PATH}/releases/.incoming`, uploads the versioned DMG, versioned
ZIP, appcast, generated `SHA256SUMS`, and generated `latest.json`, then installs
them under `${DEPLOY_PATH}/releases`. It uploads the immutable artifacts before
publishing the appcast and smoke-checks every public URL. See
[client-runbook.md](client-runbook.md#local-release-sequence).

If nginx was installed by an earlier bootstrap, re-render and reload once to
pick up the update routes:

```bash
node scripts/render-deploy-config.mjs
scp "deploy/rendered/${APP_NAME:-vibes}.nginx.conf" "$DEPLOY_USER@$DEPLOY_HOST:/etc/nginx/sites-available/$DEPLOY_DOMAIN"
ssh "$DEPLOY_USER@$DEPLOY_HOST" "nginx -t && systemctl reload nginx"
```

## Mac Release Rollback

Rollback is two separate decisions: first-download DMG traffic and Sparkle
updates. Repointing `/downloads/Vibes.dmg` changes what new website downloads
receive. It does **not** downgrade users who already installed the bad build.
Sparkle compares build numbers, so avoid forced downgrades; either remove the
bad item from the appcast for users who have not updated yet, or ship a fixed
hotfix with a higher `VIBES_BUILD_NUMBER`.

Load the deploy variables locally before running the examples:

```bash
set -a
source .env.deploy
set +a
```

Repoint the stable DMG URL at a known-good version on the Linux VPS and
restore matching public metadata. The publish script normally writes
`/downloads/latest.json` and `/downloads/SHA256SUMS`; keep those in sync because
`/download` reads `latest.json`.

```bash
GOOD_VERSION=0.2.0
GOOD_BUILD=12
GOOD_MINIMUM_MACOS=14.0

ssh "$DEPLOY_USER@$DEPLOY_HOST" bash -s -- "$DEPLOY_PATH" "$GOOD_VERSION" "$GOOD_BUILD" "$GOOD_MINIMUM_MACOS" <<'REMOTE'
set -euo pipefail
deploy_path="$1"
good_version="$2"
good_build="$3"
minimum_macos="$4"
published_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
downloads_dir="${deploy_path}/releases/downloads"

test -f "${downloads_dir}/Vibes-${good_version}.dmg"
test -f "${downloads_dir}/Vibes-${good_version}.zip"

if [[ "$(uname -s)" == "Linux" ]]; then
  ln -sfn "Vibes-${good_version}.dmg" "${downloads_dir}/Vibes.dmg.tmp"
  mv -Tf "${downloads_dir}/Vibes.dmg.tmp" "${downloads_dir}/Vibes.dmg"
else
  cp "${downloads_dir}/Vibes-${good_version}.dmg" "${downloads_dir}/Vibes.dmg.tmp"
  mv -f "${downloads_dir}/Vibes.dmg.tmp" "${downloads_dir}/Vibes.dmg"
fi

(
  cd "${downloads_dir}"
  sha256sum "Vibes-${good_version}.dmg" "Vibes-${good_version}.zip" \
    | sed 's#^\([0-9a-f]*\)  Vibes-#\1  Vibes-#' > SHA256SUMS.tmp
  mv -f SHA256SUMS.tmp SHA256SUMS
)

cat > "${downloads_dir}/latest.json.tmp" <<JSON
{
  "version": "${good_version}",
  "build": ${good_build},
  "buildString": "${good_build}",
  "minimumMacOS": "${minimum_macos}",
  "dmg": "/downloads/Vibes.dmg",
  "stableDmg": "/downloads/Vibes.dmg",
  "versionedDmg": "/downloads/Vibes-${good_version}.dmg",
  "zip": "/downloads/Vibes-${good_version}.zip",
  "versionedZip": "/downloads/Vibes-${good_version}.zip",
  "appcast": "/appcast.xml",
  "sha256": "/downloads/SHA256SUMS",
  "publishedAt": "${published_at}"
}
JSON
mv -f "${downloads_dir}/latest.json.tmp" "${downloads_dir}/latest.json"
REMOTE

curl -fsSI "https://${DEPLOY_DOMAIN}/downloads/Vibes.dmg"
curl -fsS "https://${DEPLOY_DOMAIN}/downloads/latest.json" | python3 -m json.tool
curl -fsS "https://${DEPLOY_DOMAIN}/downloads/SHA256SUMS" | grep -F "Vibes-${GOOD_VERSION}.dmg"
curl -fsS "https://${DEPLOY_DOMAIN}/downloads/SHA256SUMS" | grep -F "Vibes-${GOOD_VERSION}.zip"
```

For Sparkle, publish an appcast that omits the bad version if the goal is to
stop more users from updating to it. Generate or restore
`release/appcast/appcast.xml` without the bad item, then upload and install it on
the Linux VPS:

```bash
GOOD_VERSION=0.2.0
ROLLBACK_APPCAST=release/appcast/appcast.xml
REMOTE_APPCAST_INCOMING="/tmp/vibes-appcast-$(date -u '+%Y%m%d%H%M%S').xml"

test -f "$ROLLBACK_APPCAST"
scp "$ROLLBACK_APPCAST" "$DEPLOY_USER@$DEPLOY_HOST:$REMOTE_APPCAST_INCOMING"
ssh "$DEPLOY_USER@$DEPLOY_HOST" bash -s -- "$DEPLOY_PATH" "$REMOTE_APPCAST_INCOMING" <<'REMOTE'
set -euo pipefail
deploy_path="$1"
incoming="$2"
install -m 0644 "$incoming" "${deploy_path}/releases/appcast.xml"
rm -f "$incoming"
REMOTE

curl -fsSI "https://${DEPLOY_DOMAIN}/appcast.xml"
curl -fsS "https://${DEPLOY_DOMAIN}/appcast.xml" | grep -F "Vibes-${GOOD_VERSION}.zip"
```

Alternatively, cut a hotfix with the same `MARKETING_VERSION` or a newer
marketing version, but always with a higher `CURRENT_PROJECT_VERSION` /
`VIBES_BUILD_NUMBER` than the bad build. Then run the normal `make mac-release`
flow.

Do not try to make Sparkle force-install an older build number over a newer bad
install. That is not a normal rollback path and risks leaving users stranded on
an update channel they cannot verify.

## Profile-Icon Storage

Generated avatars are stored by the relay's filesystem store and served by the
nginx `/avatars/` alias (outside the deployed `server/` tree, like `releases/`).
Two runtime env vars control this; the templated systemd unit sets them beside
`VIBES_DB_PATH`:

- `VIBES_AVATAR_DIR` — on-disk dir the relay writes PNGs to. Defaults in the unit
  to `${DEPLOY_PATH}/avatars`, the dir the deploy script `mkdir -p`s and nginx
  serves.
- `VIBES_AVATAR_BASE_URL` — public URL prefix the slug is appended to. Defaults
  in the unit to `https://${DEPLOY_DOMAIN}/avatars`.

If both are unset in production the relay falls back to dev-only defaults
(`data/avatars` + a `http://localhost:3136/avatars` URL) and logs a warning at
startup; uploaded avatars then land where nginx does not serve them and every
client's image load 404s. Keep the unit's `Environment=` lines in place (or set
the vars in `server/.env.local`) on a fresh VPS.

The `s3` store (`VIBES_AVATAR_STORE=s3`) is a stub until R2/S3 credentials are
wired.

## Admin Area

The relay has a password-gated web admin at `/admin` for a single superuser:
dashboard, user management (devices, tokens, invites, friends, disable/enable,
delete), and a global invite view.

It is **disabled unless `VIBES_ADMIN_PASSWORD` is set**. With no password the
whole `/admin/*` tree returns 404, so an un-configured relay exposes no login
surface.

`VIBES_ADMIN_PASSWORD` is a runtime secret read by the running relay, so it lives
in a root-only env file the systemd unit loads (`EnvironmentFile=-…/server/.env.local`),
never in git or the rsync payload.

Enable it on the host:

```bash
install -m 600 /dev/null "$DEPLOY_PATH/server/.env.local"
echo "VIBES_ADMIN_PASSWORD=$(openssl rand -base64 32)" >> "$DEPLOY_PATH/server/.env.local"
systemctl restart "${SERVICE_NAME}.service"
```

Then open `https://$DEPLOY_DOMAIN/admin/login`. Rotating the password is editing
that one line and restarting; existing sessions are unaffected until they expire.

Sessions are SQLite-backed and cookie-referenced (httpOnly, Secure, SameSite=Lax,
scoped to `/admin`); only the token hash is stored. Login is per-IP rate limited
and the password compare is constant-time.

Bootstrap your own user (first invite token) once signed in:

1. `/admin/users/new` → create your user (handle + display name), keep "mint
   invite link" checked.
2. Copy the one-time `/invite/<code>` link, open it, and accept it in the Mac app
   to receive your bearer token.

The CLI (`node cli.mjs users create` / `invites create`) remains a headless
fallback.

For local development, set the password inline:

```bash
VIBES_ADMIN_PASSWORD=dev VIBES_DB_PATH=data/dev.sqlite make server-dev
# then open http://127.0.0.1:5173/admin/login
```

## Verification

```bash
dig +short "$DEPLOY_DOMAIN"
curl -sSI "$DEPLOY_URL"
curl -sS "$DEPLOY_URL"
ssh "$DEPLOY_USER@$DEPLOY_HOST" "systemctl status ${SERVICE_NAME} --no-pager -l"
```

## API Direction

The full contract lives in `docs/plans/active/spec-v2.md` (API Contract section).

Implemented so far:

- `GET /healthz`
- `GET /invite/:code` — web signup page
- `POST /invite/:code/accept` — accept an invite (creates user, token, mutual friendship)
- `POST /api/users` — create a bootstrap user
- `POST /api/invites`, `GET /api/invites`, `POST /api/invites/:id/revoke`
- `POST /api/status`, `GET /api/feed`
- `POST /api/friends/remove`, `POST /api/tokens/revoke`
- `/admin/*` — password-gated web admin (dashboard, users, invites); 404 when `VIBES_ADMIN_PASSWORD` is unset

Contract validation tests are located in [relay.test.js](file:///Users/marcusvorwaller/code/vibes/server/tests/relay.test.js). They load the contract fixtures from `shared/contract/` and verify that API requests and responses match both SvelteKit route logic and SwiftUI JSON models to prevent drift.

Still to build: broader admin tooling and packaged Mac app distribution.

Bearer token auth for v1. Identities, friend links, invites, and latest status blobs live in SQLite; the schema and migrations are in `server/src/lib/server/db.js`.

Git activity is still published as aggregate `git_stats`. The relay records one
aggregate `daily_activity` row per `(user_id, device_id, client_day)` with
cumulative `commits`, `insertions`, and `deletions`; each publish replaces that
device's totals for the day. `daily_activity.commits` powers the derived
`commit_streak` feed summary (`{days, through_day}`), which is returned only
when the merged row has visible `git_stats`. If Git stats sharing is off, the
feed returns no streak.

Upgraded clients also send one-way `commit_details` fingerprints inside the
status blob. The relay deduplicates those fingerprints across a user's devices
for the selected Vibes day, stores unique entries in `daily_commits`, and
returns only aggregate counts in `/api/feed`; raw commit hashes, branch names,
messages, filenames, repo paths, device IDs, timezones, per-day feed history,
and repo-level history stay out of feed responses.
