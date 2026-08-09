# Vibes pre-public-launch audit

Audited 2026-08-08 before a Hacker News / Reddit launch. This is a point-in-time
review of the public repository, the shipping macOS artifact, the live relay at
`vibes.opentangle.com`, and the host configuration. The live checks were
read-only; this document is the only repository change from the audit.

## Recommendation

Do not send broad public traffic yet. The app and signed release are in good
shape, but public attention would expose avoidable trust and operational risks:

1. public privacy claims conflict with actual behavior;
2. the relay runs on an unsupported OS as root, beside unrelated public services;
3. the private database is world-readable on the host and has no backup;
4. open registration plus unbounded retained data makes cheap storage abuse possible;
5. the deployed SvelteKit version has a remotely reachable denial-of-service advisory.

Complete P0 before posting. P1 can follow immediately before or during a small,
explicitly labeled beta. P2 is polish, not a launch gate.

## What is already strong

- The live 0.10.3 / build 23 DMG downloaded successfully, matched the published
  SHA-256 checksum, passed `hdiutil verify`, passed Gatekeeper as `Notarized
  Developer ID`, had a valid Developer ID signature and hardened runtime, and
  had valid stapled tickets on both the DMG and app.
- HTTPS is valid and the app serves HSTS, CSP, `nosniff`, referrer policy, and
  frame-denial headers. The relay binds to loopback behind nginx.
- The live service is active with zero recorded restarts, `/healthz` returns 200,
  and SQLite `quick_check` returns `ok` at migration 8.
- Raw bearer tokens, invite codes, link codes, and admin sessions are hashed at
  rest. Admin cookies are HttpOnly, Secure over HTTPS, SameSite=Lax, and scoped
  to `/admin`.
- Request bodies and avatar dimensions have caps, PNG metadata is stripped,
  SQL parameters are used consistently, and admin sort interpolation is
  allowlisted.
- The scanner publishes aggregate Git data rather than repo paths, branches,
  commit messages, filenames, file contents, editor/process history, or
  transcripts.
- Under supported Node 22, all 165 relay tests pass. `make client` succeeds.
  The first test attempt under unsupported Node 26 failed because the native
  SQLite module had a Node ABI mismatch; that is a tooling issue captured in P2.

## P0 — complete before public posting

### P0.1 Make every privacy claim literally true

**Risk:** Vibes leads with privacy. Public reviewers can disprove several claims
directly from the open source, which would cause more damage than modestly less
ambitious copy.

**Observed conflicts:**

- The privacy page says repo names never leave the Mac
  (`server/src/routes/privacy/+page.svelte:37-44`), but a newly added repo uses
  its folder name as the alias (`client/Vibes/AppModel.swift:700-708`) and both
  per-repo alias sharing and the global repo-alias card default to on
  (`client/Vibes/Models.swift:68-118`). The in-app repository page is more honest:
  it says the repo name is shared (`client/Vibes/ContentView.swift:683-690`).
- The page says AI prompts never leave the Mac, but avatar upload sends
  `X-Avatar-Prompt` (`client/Vibes/GitScanner.swift:262-275`) and the relay stores
  that prompt (`server/src/lib/server/relay.js:1436-1474`).
- It says friends see “minutes coded,” but no editor timer or minute metric
  exists. Vibes reports commits, files, and line churn.
- It says a person is online only while actively coding. In fact, an online app
  scans and republishes every 180 seconds whether or not Git activity changed
  (`client/Vibes/AppModel.swift:1083-1091`); the relay treats that heartbeat as
  online for ten minutes.
- It says “your group only” and “nobody else,” but Network Pulse aggregates every
  relay user's activity and sends the same result to every viewer. Its anonymity
  floor is only three contributors (`server/src/lib/server/relay.js:38-44` and
  `:851-960`). Three is not resistant to subtraction by two participants.
- It says “no accounts” and “no sign-up,” but first launch creates a durable relay
  user and bearer token through public registration
  (`server/src/routes/api/register/+server.js:6-15`). The accurate claim is “no
  email address or password required.”
- Optional weather sends a city to Open-Meteo geocoding or coordinates to
  Open-Meteo forecast APIs (`client/Vibes/WeatherProvider.swift`), so “your
  location never leaves this Mac” (`client/Vibes/ContentView.swift:936-955`)
  needs to say “is not sent to Vibes or friends” and disclose Open-Meteo.
- nginx keeps IP address, user-agent, and request-path logs for fourteen days.
  Invite secrets appear in `/i/<code>` and `/invite/<code>` paths; 36 matching
  requests were present in the current rotated log set.

**Recommended change:**

- First, remove transmission/storage that is unnecessary: do not send or store
  avatar prompts; turn repo-alias sharing off by default or clearly obtain
  consent when a repo is added; disable the global Network Pulse for launch
  unless it becomes a separate informed opt-in with a stronger privacy design.
- Then replace the short marketing summary with a real privacy notice covering:
  exact fields sent; defaults; optional music/weather/avatar behavior and third
  parties; iCloud Keychain token sync; server-side status, daily aggregate,
  fingerprint, avatar, admin-audit, and access-log retention; who can see each
  field; account deletion; a privacy/security contact; and policy version/date.
- Remove Google Fonts requests from `MarketingShell.svelte:29-36`. They are
  inconsistent with the system-font design, create an unnecessary third-party
  connection, and are currently blocked by the site's own CSP anyway.
- Configure a Vibes-specific nginx access log that does not record secret invite
  paths (or disable access logging for those locations) and document the actual
  retention period.

**Proof:** Capture a status/avatar/network request from a clean release build,
list every outbound host and field, compare it line by line with the notice, and
verify invite codes do not appear in new access logs.

### P0.2 Move the relay to a supported, least-privilege host

**Risk:** A compromise of this process or any unrelated public service on the
host can expose private social/activity data and bearer-token hashes. Running
the Node process as root turns an application exploit into a host compromise.

**Live findings:**

- The host runs Ubuntu 24.10. Canonical ended support on 2025-07-10; it no longer
  receives Ubuntu security notices or package updates. Use Ubuntu 24.04 LTS or
  another currently supported distribution. Canonical recommends 24.04 LTS for
  long-term support: <https://documentation.ubuntu.com/release-notes/24.10/>.
- `vibes.service` runs as `User=root` even though the checked-in template has a
  configurable service user (`deploy/vibes.service.template:7-32`).
- `/var/www/vibes/data` is `0755` and `vibes.sqlite` is `0644`. Any local account
  can read the database.
- UFW is inactive. In addition to 22/80/443, the shared host exposes TCP 3100,
  5001, 5010–5070, 8080, and 8443 publicly for unrelated workloads.
- Root SSH login is allowed with keys. Password authentication is disabled.

**Recommended change:** Provision a fresh supported LTS host, preferably
dedicated to Vibes. Run the app as a non-login `vibes` user; use `0700` for data
and avatar directories, `0600` for the database and secret file, and `UMask=0077`.
Add systemd hardening such as `NoNewPrivileges=true`, `PrivateTmp=true`,
`ProtectSystem=strict`, `ProtectHome=true`, and narrow `ReadWritePaths` after
testing avatar and SQLite writes. Allow only SSH, HTTP, and HTTPS in both the
provider firewall and host firewall. If the shared host remains, inventory and
patch every exposed workload because its risk boundary is the Vibes database.

**Proof:** From the Internet, only intended ports answer. `systemctl show` names
the dedicated user. That user can write the DB/avatar directories; another
unprivileged account cannot read them. Deploy, restart, avatar upload, status
publish, and feed all pass under the hardened unit.

### P0.3 Add encrypted backups and prove recovery

**Risk:** The relay is now the only copy of friendships, tokens, latest status,
daily aggregates, and uploaded avatars. Disk loss or a bad migration loses the
network and makes existing clients unusable.

**Live finding:** No Vibes backup timer, cron entry, or backup artifact exists on
the host. The current deployment updates the live tree in place and does not
take a pre-migration database backup (`scripts/deploy-server.sh:41-72`).

**Recommended change:** Create a dedicated timer that uses SQLite's online backup
API or `.backup` command, includes avatar files, encrypts before off-host upload,
and retains daily plus periodic snapshots. Do not copy only the main SQLite file
while WAL writes may be active. Add a pre-deploy snapshot and document exact
restore/rollback commands without storing bearer secrets in logs.

**Proof:** Restore the latest backup into a disposable host, run `quick_check`,
start the exact release, authenticate a copied test account, load its feed and
avatar, and record the restore date/result.

### P0.4 Bound registration and retained-data abuse

**Risk:** Hacker News or Reddit traffic changes the relay from a seven-user
friend service into an unauthenticated public write target. A modest script can
grow users, avatar files, and `daily_commits` until disk or operator attention is
exhausted.

**Evidence:**

- `/api/register` is public, and the unused legacy `/api/users` endpoint also
  creates users without authentication or tokens
  (`server/src/routes/api/users/+server.js:1-18`).
- Rate limiting is a process-local `Map` keyed by IP and route, resets on process
  restart, has no distributed/global budget, and never expires inactive keys
  (`server/src/lib/server/http.js:5-29`).
- Statuses accept 256 KiB although the product spec promises 32 KiB
  (`server/src/lib/server/relay.js:5-12`; `docs/plans/active/spec-v2.md:291-293`).
  Arbitrary card data is retained, and every new valid-looking commit id is
  inserted into `daily_commits` without a server-side per-day count limit
  (`server/src/lib/server/relay.js:590-625` and `:1005-1050`).
- Each avatar upload can be 1.5 MB. Regeneration intentionally retains every old
  DB row and public immutable file, and clearing the avatar retains history
  (`server/src/lib/server/relay.js:1436-1440` and `:1515-1533`).

**Recommended change:** Remove `/api/users`. Decide explicitly between:

- an invite-gated beta, which best matches “private groups” and makes the invite
  credential part of atomic registration; or
- open registration with durable edge limits, a global/day capacity budget,
  per-account status/avatar quotas, maximum devices/invites, retention/garbage
  collection, and a clean `503 capacity_limited` mode.

In either case enforce the 32 KiB contract, a maximum card count and depth,
known-card schemas and numeric ceilings, at most 150 commit details per status,
and a retained daily-commit bound. Replace prior avatar bytes on regeneration
unless the user explicitly asks for history.

**Proof:** Abuse tests from many IP keys and after a process restart cannot exceed
the documented global/account budgets; disk use stabilizes after retention runs;
normal first-user, friend-invite, second-device, status, and avatar journeys pass.

### P0.5 Fix pseudonymous commit identifiers or disclose them accurately

**Risk:** The claimed “one-way commit fingerprint” is deterministic
`SHA256("vibes.git.commit.v1:" + rawCommitHash)`
(`client/Vibes/GitScanner.swift:109-113`). Anyone who knows a public commit hash
can compute the stored value and correlate that commit with a Vibes account if
they gain DB/operator access. The relay retains identifiers and commit times in
`daily_commits`; hiding them from feed responses does not make them unlinkable.

**Recommended change:** For launch, the simplest privacy-preserving choice is to
remove per-commit identifiers and accept best-effort multi-device totals. If
exact dedupe is important, design an account-scoped keyed identifier whose
secret is not available in a database-only compromise, define how new devices
obtain it, rotate/migrate the scheme, and delete old deterministic fingerprints.
At minimum call the current values pseudonymous identifiers in the privacy
notice, not anonymous or irreversible data.

**Proof:** Given a known public commit hash and a database dump, an auditor cannot
link it to a retained identifier under the new scheme; old linkable rows are gone.

### P0.6 Upgrade the deployed SvelteKit runtime

**Risk:** `@sveltejs/kit` 2.63.0 is affected by an unauthenticated CPU-exhaustion
ReDoS in `Accept` header negotiation. The patched version is 2.70.2:
<https://github.com/advisories/GHSA-29g2-3rmr-qm68>.

**Evidence:** `server/package-lock.json:952-953` pins 2.63.0. `npm audit` reports
the SvelteKit finding; the broader development tree reports 11 advisories (one
critical, three high, six moderate, one low), while `npm audit --omit=dev`
reports none. SvelteKit is declared as a development dependency but its adapter
output is the production server, so the runtime advisory still matters.

**Recommended change:** Update SvelteKit to at least 2.70.2 (currently within the
declared semver range), refresh compatible Svelte/adapter packages, rebuild, and
redeploy. Triage development-only Vite/Vitest/PostCSS advisories separately;
they do not justify exposing a dev server or running untrusted builds.

**Proof:** Full tests and production build pass, `npm audit` no longer reports a
production-relevant SvelteKit advisory, the live artifact identifies the updated
bundle, and a bounded long-`Accept` regression test does not consume excessive CPU.

## P1 — complete before calling it generally available

### P1.1 Make the relay authoritative about time and payload shape

`updated_at` only has to parse as a date (`server/src/lib/server/relay.js:602-625`).
A client can publish a far-future timestamp and remain “online,” dominate merge
sorting, and poison daily history. Reject timestamps outside a small skew window
or use `server_received_at` for presence, sorting, and retention. Validate that
the client day and boundaries match the account timezone within an allowed skew.
Reject non-finite/oversized Git counts, excessive nesting, invalid commit times,
unknown fields where the server interprets the card, and conflicting card types.

### P1.2 Provide real account export and deletion

Users can revoke devices and remove friends, but cannot export or delete their
relay account. Admin deletion removes relational rows
(`server/src/lib/server/admin.js:396-416`) but does not remove filesystem avatar
objects even though the storage adapter has `remove`
(`server/src/lib/server/avatarStore.js:35-61`). Add authenticated export and
delete capabilities through the shared application/API boundary and native UI.
Deletion must revoke tokens, remove rows, remove current and historical avatar
bytes, invalidate synced-account recovery, and state how long backups retain the
deleted copy. Test idempotence and interrupted cleanup.

### P1.3 Deploy atomically with a tested rollback

The deploy script rsyncs with `--delete` into the live source directory, runs
`npm ci` and a build there, restarts, then checks only `/healthz`
(`scripts/deploy-server.sh:41-104`). Build into a versioned release directory,
run migrations with a pre-deploy backup, switch one symlink, restart, exercise a
status/feed read-write smoke account, and retain the prior compatible release.
Document when a database migration prevents binary rollback.

### P1.4 Add monitoring for the things that can strand users

Alert on public health, certificate expiry, process restarts, disk/inode use,
SQLite integrity/backup age, 5xx/429 rate, login failures, and failed deployment.
The shared host currently reports `certbot.service` failed twice daily because
three unrelated domains cannot renew. The Vibes certificate itself is valid
through 2026-11-03, but a permanently failed global renewal unit trains the
operator to ignore failures. Remove/fix stale renewals and alert per certificate.

### P1.5 Publish source-to-binary provenance and a security contact

The GitHub repository is public and MIT licensed, but the website does not link
it, there are no Git tags or GitHub Releases, no Actions workflows, no branch
protection, no `SECURITY.md`, and `/.well-known/security.txt` returns 404. For
each future release, tag the exact source commit, attach checksums/artifacts or
link the canonical downloads, and run build/tests plus dependency/secret scans
in CI. Link “Source” from the site. Add a private vulnerability-reporting route,
supported-version policy, and `security.txt`. Do not promise reproducible builds
until they are actually reproducible.

### P1.6 Prove the clean two-person launch journey

Run a disposable end-to-end scenario using the shipping DMG and live-equivalent
relay: clean install, first identity, repo selection, inspect exact publish JSON,
second identity, invite open/accept, reciprocal feed, Offline, app sleep/stale
presence, quit, relaunch, device link/revoke, token loss, avatar replace/delete,
account delete, auto-update, and restore from backup. Preserve screenshots and
HTTP assertions as release evidence. This is more valuable than adding broad
unit coverage around already-tested helpers.

## P2 — high-value polish after the safety floor

### P2.1 Make `make check` fail clearly on unsupported Node

The README says Node 20, 22, or 24, but `make check` under Node 26 produced 127
misleading test failures from a native-module ABI mismatch. Add `.tool-versions`
or `.mise.toml`/`.nvmrc`, plus a preflight that exits once with the supported
range and remediation. Keep host and CI on the same major.

### P2.2 Make the public API discoverable to agents and self-hosters

The app owns identities, presence, invites, devices, and friendships, and those
capabilities do have non-interactive HTTP paths. Document them from one contract:
authentication, schemas, limits, refusal codes, curl examples, lifecycle, and
privacy semantics. Expand `shared/contract` to cover registration, invites,
devices, deletion/export, and the optional cards, then test adapters against it.

### P2.3 Tighten public web hygiene

Add `robots.txt`, canonical source/support links, an accurate compatibility line,
and the correct DMG MIME type (the live exact download currently returns
`application/octet-stream` despite the template's intended type). Remove the
external font tags and use the system stack. Consider suppressing the nginx
version token. Keep the existing CSP and security headers.

### P2.4 Keep release metadata synchronized

The shipping profile inspected from 0.10.3 expires in 2044, while
`docs/client-runbook.md` says the checked-in profile expires in 2027. Generate
the runbook fact from the actual profile or verify it in release preflight. Also
ensure the appcast, `latest.json`, checksums, release notes, source commit, and
marketing version are checked as one publication transaction.

### P2.5 Add lightweight dependency maintenance

Enable Dependabot or Renovate and a scheduled supported-Node audit/build. Keep
runtime advisories distinct from dev-server/test-runner findings so the signal
stays useful. Update the Svelte/Vite/Vitest generation deliberately rather than
using `npm audit fix --force` without compatibility review.

## Launch gate

Post publicly only when all of the following are true:

- [ ] Every privacy sentence matches a captured shipping request and retention map.
- [ ] Global Pulse is disabled or explicitly consented to and defensibly private.
- [ ] Avatar prompts and old avatar bytes are not retained unexpectedly.
- [ ] The relay runs on a supported OS as a dedicated unprivileged user.
- [ ] Private directories/files are not readable by unrelated local accounts.
- [ ] Only intended ports are publicly reachable.
- [ ] Encrypted off-host backup and disposable restore proof are current.
- [ ] Registration, status history, commit details, devices/invites, and avatars have durable quotas.
- [ ] The legacy unauthenticated `/api/users` creation route is gone.
- [ ] SvelteKit is at a patched version and the deployed build is verified.
- [ ] A clean two-person shipping-DMG journey passes against the release relay.
- [ ] Users have a documented support, security, export, and deletion path.

## Audit evidence snapshot

- Live relay: 7 users, 9 active tokens, 9 status rows, 0 open invites; DB
  `quick_check=ok`; migration 8.
- Live service: active/enabled, zero restarts since 2026-06-25, Node 20.16.0,
  loopback port 3136, approximately 74 MB resident at inspection.
- TLS: Let's Encrypt ECDSA certificate issued 2026-08-05, expires 2026-11-03.
- Release: 0.10.3, build 23, published 2026-08-09T01:01:24Z; checksum
  `d9d6e3115d006d0bba4d40ed11e17b8df37d56d12958c0f236f973ba4fba1813`.
- Tests: relay 165/165 passing under Node 22.23.1; macOS Debug build succeeded.
- Repository at inspection: clean `main` at `c77620a`; no tags, GitHub Releases,
  Actions workflows, or branch protection.

Because host and dependency state drift, refresh the live portions of this audit
immediately before the post rather than treating this file as a permanent attestation.
