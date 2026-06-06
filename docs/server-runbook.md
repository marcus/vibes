# Server Runbook

The Vibes relay target is `https://vibes.opentangle.com`.

The production scaffold mirrors the Chirp deployment:

- VPS: `146.190.117.215`
- deploy path: `/var/www/vibes`
- systemd service: `vibes.service`
- local bind: `127.0.0.1:3136`
- reverse proxy: nginx
- TLS: certbot

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
DEPLOY_HOST=146.190.117.215 DEPLOY_PATH=/var/www/vibes make deploy
DRY_RUN=1 make deploy
```

## First-Time Bootstrap

1. Create the `vibes.opentangle.com` DNS record in Cloudflare.
2. Issue a certificate on the VPS:

```bash
ssh root@146.190.117.215 \
  'certbot certonly --dns-cloudflare --dns-cloudflare-credentials /root/.cloudflare-dns.ini --dns-cloudflare-propagation-seconds 60 -d vibes.opentangle.com'
```

3. Install nginx and systemd units:

```bash
scp deploy/nginx-vibes.opentangle.com.conf root@146.190.117.215:/etc/nginx/sites-available/vibes.opentangle.com
scp deploy/vibes.service root@146.190.117.215:/etc/systemd/system/vibes.service
ssh root@146.190.117.215 \
  'ln -sf /etc/nginx/sites-available/vibes.opentangle.com /etc/nginx/sites-enabled/vibes.opentangle.com && systemctl daemon-reload && systemctl enable vibes.service && nginx -t && systemctl reload nginx'
```

4. Deploy:

```bash
make deploy
```

## Verification

```bash
dig +short vibes.opentangle.com
curl -sSI https://vibes.opentangle.com/healthz
curl -sS https://vibes.opentangle.com/healthz
ssh root@146.190.117.215 'systemctl status vibes --no-pager -l'
```

## API Direction

Initial routes:

- `GET /healthz`
- `POST /api/status`
- `GET /api/feed`
- `POST /api/invites`
- `POST /api/invites/accept`

Use simple token auth for v1. Store identities, friend links, invites, and latest status blobs in SQLite.
