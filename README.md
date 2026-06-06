# Vibes

A small macOS app for private, ambient presence among friends who are building things together.

Vibes shows who is around, what kind of coding day they are having, and coarse daily stats from local Git repositories. The app is designed for small friend groups, privacy-respecting defaults, and a lightweight native desktop experience.

## Status

Hackathon scaffold. The repo is ready for client and relay implementation, with a checked-in Xcode project, a minimal Node relay shell, deploy scripts, and runbooks.

## Project Shape

- `client/`: native SwiftUI macOS app project.
- `server/`: tiny Node relay service shell.
- `deploy/`: nginx and systemd templates for `vibes.opentangle.com`.
- `scripts/`: local and server deployment helpers.
- `docs/plans/active/spec-v1.md`: product and implementation plan.

## Requirements

- macOS with Xcode 26 or newer.
- Node.js 22 or newer for the relay.
- GitHub CLI for repo administration.
- SSH access to the Open Tangle VPS for deployment.

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

Run the relay locally:

```bash
make server
curl http://127.0.0.1:3136/healthz
```

Build the macOS app from the command line:

```bash
make client
```

## Relay

The relay is intentionally small. Its first production target is:

```text
https://vibes.opentangle.com
```

For v1 it should store user identity, friend invites, friend relationships, and latest status blobs. SQLite is the expected database for the first implementation.

## Client

The client is a SwiftUI macOS app. The first build target is a small mostly chromeless desktop window with:

- manual status
- Broadcasting / Quiet / Offline mode
- configured local Git repo scanner
- aggregate daily stats
- friend feed from the relay
- optional menu bar companion

## Development

Useful commands:

```bash
make check       # run available validation
make client      # build the macOS target
make server      # run the local relay shell
make deploy      # deploy the relay shell to the configured VPS
```

Read [AGENTS.md](AGENTS.md) before starting implementation work. It captures repo conventions, privacy constraints, and suggested first tasks.

## Deployment

The deploy scaffold mirrors Chirp's Open Tangle setup:

- nginx terminates TLS.
- systemd runs Node on `127.0.0.1:3136`.
- app files live under `/var/www/vibes`.
- certbot manages certificates for `vibes.opentangle.com`.

See [docs/server-runbook.md](docs/server-runbook.md) for bootstrap and deploy details.

## License

MIT. See [LICENSE](LICENSE).
