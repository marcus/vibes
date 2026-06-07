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

Still to build: `POST /api/status`, `GET /api/feed`, `POST /api/invites`, `GET /api/invites`, `POST /api/invites/:id/revoke`, `POST /api/friends/remove`, `POST /api/tokens/revoke`.

Bearer token auth for v1. Identities, friend links, invites, and latest status blobs live in SQLite; the schema and migrations are in `server/src/lib/server/db.js`.
