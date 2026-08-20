# Vibes

Always check if you are running in Sidecar: run `sidecar --agents` for capabilities.

A small macOS app for private, ambient presence among friends who are building things together.

Vibes shows which friends are online and coding, plus coarse daily stats from local Git repositories. The app is designed for small friend groups, privacy-respecting defaults, and a lightweight native desktop experience.

## Status

Fully functional implementation. The repository includes a SwiftUI macOS client with local Git scanning and presence status derivation, a SvelteKit relay backed by SQLite with schema migrations, an invite-based friend flow, contract schema testing, and deployment playbooks.

## Project Shape

- `client/`: native SwiftUI macOS app project.
- `server/`: SvelteKit relay (API + web signup) backed by SQLite.
- `deploy/`: nginx and systemd templates for a relay host.
- `scripts/`: local and server deployment helpers.
- `docs/plans/active/spec-v2.md`: product and implementation plan.

## Requirements

- macOS with Xcode 26 or newer.
- Node.js 20, 22, or 24 for the relay. Node 26 is not supported by the current SQLite native dependency.
- GitHub CLI for repo administration.
- SSH access to a VPS-style host for deployment.

## Quick Start

```bash
git clone git@github.com:marcus/vibes.git
cd vibes
make check
```

Open the macOS app:

```bash
open client/Vibes.xcodeproj
```

Run the relay locally (dev server with hot reload):

```bash
cd server && npm install
cd .. && make server-dev
curl http://127.0.0.1:5173/healthz
```

Build the macOS app from the command line:

```bash
make client
```

## Relay

The relay is intentionally small. Set `DEPLOY_DOMAIN`, `DEPLOY_HOST`, and related values in `.env.deploy` before deploying to a server.

For v1 it should store user identity, friend invites, friend relationships, and latest status blobs. SQLite is the expected database for the first implementation.

## Client

The client is a SwiftUI macOS app. The first build target is a small mostly chromeless desktop window with:

- manual status
- online / offline presence, with a one-tap Offline toggle
- configured local Git repo scanner
- aggregate daily stats
- friend feed from the relay
- optional menu bar companion

## Development

Useful commands:

```bash
make check       # run server tests + build the macOS target
make client      # build the macOS target
make server-dev  # run the relay dev server (hot reload)
make server      # build and run the production relay
make server-check # run the relay test suite
make deploy      # deploy the relay to the configured VPS
```

Read [AGENTS.md](AGENTS.md) before starting implementation work. It captures repo conventions, privacy constraints, and suggested first tasks.

## Deployment

The deploy scaffold expects a VPS-style host:

- nginx terminates TLS.
- systemd runs Node on `SERVICE_HOST:SERVICE_PORT`.
- app files live under `DEPLOY_PATH`.
- certbot manages certificates for `DEPLOY_DOMAIN`.

See [docs/server-runbook.md](docs/server-runbook.md) for bootstrap and deploy details.

## Releases

The macOS client ships as a Developer ID–signed, notarized app with Sparkle auto-updates (planned). Release scripts live in `scripts/` (`release-mac.sh`, `generate-appcast.sh`, `setup-notary.sh`). See [docs/client-runbook.md](docs/client-runbook.md#signed-release--notarization) for the signing, notarization, and publishing flow.

## License

MIT. See [LICENSE](LICENSE).
