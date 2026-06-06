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

```bash
make server
curl http://127.0.0.1:3136/healthz
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

Initial routes:

- `GET /healthz`
- `POST /api/status`
- `GET /api/feed`
- `POST /api/invites`
- `POST /api/invites/accept`

Use simple token auth for v1. Store identities, friend links, invites, and latest status blobs in SQLite.
