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

- `https://${DEPLOY_DOMAIN}/appcast.xml` → `${DEPLOY_PATH}/releases/appcast.xml` (no-cache)
- `https://${DEPLOY_DOMAIN}/downloads/<archive>` → `${DEPLOY_PATH}/releases/downloads/<archive>` (versioned, immutable, long-cached)
- `https://${DEPLOY_DOMAIN}/downloads/Vibes.dmg` → stable first-download URL (no-cache), overwritten each release for the website button

These `location` blocks live in [nginx.conf.template](file:///Users/marcusvorwaller/code/vibes/deploy/nginx.conf.template), so re-rendering and
reinstalling the nginx config (bootstrap steps 3–4) enables them. The
`${DEPLOY_PATH}/releases` directory sits outside the rsync'd `server/` tree, so
`make deploy` never touches published releases.

Publishing is part of the **client** release flow, not the relay deploy: after
building a signed/notarized app and generating the appcast, run
`scripts/publish-update.sh` (creates the dir on the host, uploads archives then
the appcast, verifies HTTP 200). See [client-runbook.md](client-runbook.md#signed-release--notarization).

If nginx was installed by an earlier bootstrap, re-render and reload once to
pick up the update routes:

```bash
node scripts/render-deploy-config.mjs
scp "deploy/rendered/${APP_NAME:-vibes}.nginx.conf" "$DEPLOY_USER@$DEPLOY_HOST:/etc/nginx/sites-available/$DEPLOY_DOMAIN"
ssh "$DEPLOY_USER@$DEPLOY_HOST" "nginx -t && systemctl reload nginx"
```

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

The full contract lives in `docs/plans/active/spec-v1.md` (API Contract section).

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
