# Vibes pre-public-launch audit

Audited 2026-08-08 before a Hacker News / Reddit launch. Updated the same day
after the product owner confirmed that sharing repository names, aggregate Git
activity, avatar prompts, presence heartbeats, Network Pulse, weather results,
and ordinary server access data is intentional. This is a point-in-time review
of the public repository, shipping macOS artifact, live relay at
`vibes.opentangle.com`, and host configuration.

## Recommendation

Do not send broad public traffic yet. The privacy mismatch found in the original
audit is resolved by publishing an accurate notice instead of removing intended
features. Four genuine security and operational risks remain P0:

1. the relay runs on an unsupported OS as root, with a world-readable database;
2. the relay has no backup or proven recovery path;
3. public registration and retained writes have insufficient abuse bounds;
4. the deployed SvelteKit version has a remotely reachable denial-of-service
   advisory.

Complete P0 before posting. P1 can follow during a small, explicitly labeled
beta. P2 is valuable polish rather than a launch gate.

## Product privacy posture

Vibes is a social app whose purpose is to share selected coding activity. The
accepted boundary is:

- **Intentionally leaves the Mac:** relay user ID, handle, and display name;
  presence and manual status; commits, files changed, insertions, deletions, and
  repositories touched; repository names or aliases; local-day metadata;
  derived streaks and churn baselines; optional music and weather cards; saved
  profile-icon images, prompts, and styles; and up to 150 deterministic commit
  fingerprints per qualifying day/status for cross-device deduplication.
- **Aggregate service-wide sharing:** Network Pulse summarizes all relay users
  over 14 days and is returned to every signed-in user. Numeric values are
  suppressed below three contributors.
- **Operational collection:** account, device, token, invite, friendship,
  status, avatar, and admin-audit records; IP address, path, referrer, user agent,
  and response metadata in web-server access logs.
- **Invite capability:** anyone holding a still-open invite URL can retrieve the
  inviter's display name without signing in. Invite URLs should be treated as
  secrets until accepted, revoked, or expired.
- **Stays local by design:** source code, file contents, raw repository paths,
  branch names, commit messages, filenames, local Git identity, editor/process
  history, coding-tool attribution, and agent transcripts. User-entered status,
  alias, and avatar-prompt fields are exceptions because they are shared as
  entered.

The public privacy page now states these flows, the ten-minute presence window,
that Offline hides presence without stopping periodic activity publication,
Open-Meteo requests, the full bearer credential synchronized through iCloud
Keychain, relay/admin/invite-holder visibility,
the absence of end-to-end encryption, current retention behavior, public avatar
URLs, deletion limitations, and a contact address. This resolves the original
P0 privacy-copy finding. It does not convert the lifecycle limitations below
into security guarantees.

## What is already strong

- The live 0.10.3 / build 23 DMG matched the published SHA-256 checksum, passed
  `hdiutil verify`, passed Gatekeeper as `Notarized Developer ID`, had a valid
  Developer ID signature and hardened runtime, and had valid stapled tickets on
  both the DMG and app.
- HTTPS is valid and the app serves HSTS, CSP, `nosniff`, referrer policy, and
  frame-denial headers. The relay binds to loopback behind nginx.
- The live service is active with zero recorded restarts, `/healthz` returns 200,
  and SQLite `quick_check` returns `ok` at migration 8.
- Raw bearer tokens, invite codes, link codes, and admin sessions are hashed at
  rest. Admin cookies are HttpOnly, Secure over HTTPS, SameSite=Lax, and scoped
  to `/admin`.
- Request bodies and avatar dimensions have caps, PNG metadata is stripped, SQL
  parameters are used consistently, and admin sort interpolation is allowlisted.
- The scanner does not publish source code, raw paths, branches, commit messages,
  filenames, file contents, editor/process history, local Git identity, coding-
  tool attribution, or transcripts.
- Under supported Node 22, all 165 relay tests pass. `make client` succeeds. The
  first server test attempt under unsupported Node 26 failed because the native
  SQLite module had a Node ABI mismatch; that tooling issue is captured in P2.

## P0 — complete before public posting

### P0.1 Move the relay to a supported, least-privilege host

**Risk:** A compromise of this process or any unrelated public service on the
host can expose private social/activity data and bearer-token hashes. Running
the Node process as root turns an application exploit into a host compromise.

**Live findings:**

- The host runs Ubuntu 24.10, which reached end of life on 2025-07-10 and no
  longer receives Ubuntu security updates. Use Ubuntu 24.04 LTS or another
  supported distribution.
- `vibes.service` runs as `User=root`.
- `/var/www/vibes/data` is `0755` and `vibes.sqlite` is `0644`, so any local
  account can read the database.
- UFW is inactive. In addition to 22/80/443, the shared host exposes TCP 3100,
  5001, 5010–5070, 8080, and 8443 publicly for unrelated workloads.
- Root SSH login is allowed with keys. Password authentication is disabled.

**Recommended change:** Provision a supported LTS host, preferably dedicated to
Vibes. Run the app as a non-login `vibes` user; use `0700` for data/avatar
directories, `0600` for the database and secret file, and `UMask=0077`. Add
systemd hardening after testing SQLite and avatar writes. Allow only intended
ports in provider and host firewalls. If the shared host remains, inventory and
patch every exposed workload because it shares Vibes' risk boundary.

**Proof:** Only intended ports answer from the Internet. The dedicated service
user can write required paths; another unprivileged account cannot read them.
Deploy, restart, avatar upload, status publish, and feed all pass under the
hardened unit.

### P0.2 Add encrypted backups and prove recovery

**Risk:** Friendships, tokens, statuses, aggregates, and avatars currently have
no recoverable server-side copy. Disk loss or a bad migration can strand every
existing client.

**Live finding:** No Vibes backup timer, cron entry, or backup artifact exists on
the host. Deployment updates the live tree in place and does not take a
pre-migration database backup (`scripts/deploy-server.sh:41-72`).

**Recommended change:** Back up SQLite through its online backup API or `.backup`
command, include avatars, encrypt before off-host upload, and retain daily plus
periodic snapshots. Add a pre-deploy snapshot and exact restore/rollback steps.

**Proof:** Restore to a disposable host, run `quick_check`, start the same
release, authenticate a copied test account, and load its feed and avatar.

### P0.3 Bound registration and retained-data abuse

**Risk:** Public attention turns the relay into an unauthenticated write target.
A small script can grow users, avatar files, and commit history until disk or
operator attention is exhausted.

**Evidence:**

- `/api/register` is public; unused legacy `/api/users` also creates users
  without authentication or tokens.
- Rate limiting is process-local, resets on restart, has no service-wide budget,
  and retains inactive IP keys for the process lifetime.
- Statuses accept 256 KiB although the product spec says 32 KiB. Arbitrary card
  data and each new valid-looking commit fingerprint can be retained without a
  server-side per-account/day ceiling.
- Each avatar upload can be 1.5 MB. Regeneration retains every old database row
  and public immutable file; clearing the avatar retains that history.

**Recommended change:** Remove `/api/users`. Either invite-gate registration, or
keep it open with durable edge limits, a global daily capacity budget,
per-account status/avatar/device/invite quotas, retention and garbage collection,
and a clean capacity-limited response. Enforce the 32 KiB contract, known card
schemas and numeric ceilings, a commit-detail limit, and a retained commit bound.

**Proof:** Abuse tests across many IP keys and after restart cannot exceed the
documented global/account budgets; disk use stabilizes after retention; normal
registration, invite, second-device, status, and avatar journeys still pass.

### P0.4 Upgrade the deployed SvelteKit runtime

**Risk:** `@sveltejs/kit` 2.63.0 is affected by an unauthenticated CPU-exhaustion
ReDoS in `Accept` header negotiation. The patched version is 2.70.2:
<https://github.com/advisories/GHSA-29g2-3rmr-qm68>.

**Evidence:** `server/package-lock.json` pins 2.63.0. `npm audit` reports the
SvelteKit finding. SvelteKit is declared as a development dependency, but its
adapter output is the production server, so the runtime advisory matters.

**Recommended change:** Update SvelteKit to at least 2.70.2, refresh compatible
Svelte/adapter packages, rebuild, test, and redeploy. Triage build-only
Vite/Vitest/PostCSS findings separately.

**Proof:** Tests and production build pass, the advisory is gone, and a bounded
long-`Accept` regression test does not consume excessive CPU.

## P1 — complete before calling it generally available

### P1.1 Make the relay authoritative about time and payload shape

A client can publish a far-future `updated_at`, remain online, dominate merge
sorting, and poison daily history. Use `server_received_at` for presence,
sorting, and retention or reject timestamps outside a small skew window. Also
validate day/timezone consistency, finite Git counts, card schemas, nesting,
commit times, and conflicting card types.

### P1.2 Provide real account export, deletion, and retention controls

Users cannot export or delete their account themselves. Admin deletion removes
account-linked database rows but retains a handle in its deletion audit entry
and does not remove avatar files, even though the storage adapter supports
removal. Add authenticated export/delete through the shared application/API
boundary and native UI. Deletion should revoke tokens, remove current and
historical avatar bytes, invalidate synced-account recovery, and define backup
retention. Add automatic retention periods for stale statuses, commit
fingerprints, and unused avatar history.

This is a meaningful privacy and lifecycle improvement, but it is not evidence
that the accepted activity-sharing model is unsafe. The public notice now
describes the current limitation instead of promising deletion that does not
exist.

### P1.3 Reduce correlation and invite-log exposure

The commit fingerprint is deterministic
`SHA256("vibes.git.commit.v1:" + rawCommitHash)`. It is appropriate to call it
pseudonymous, not anonymous: an operator or database reader who knows a public
commit hash can compute and match it. The privacy notice now discloses this.
Account-scoped keyed fingerprints would reduce database-only correlation if that
threat becomes important.

nginx also records invite codes embedded in request paths. Configure a
Vibes-specific log format or location rule that redacts those paths. This does
not require removing IP logging; IP, user-agent, status, and timing can remain
available for operations.

### P1.4 Deploy atomically with a tested rollback

The deploy script updates the live source tree, installs/builds there, restarts,
then checks only `/healthz`. Build into a versioned release directory, take a
pre-migration backup, switch one symlink, restart, run an authenticated
read/write smoke journey, and retain the prior compatible release.

### P1.5 Add monitoring for the things that can strand users

Alert on health, certificate expiry, restarts, disk/inodes, SQLite integrity,
backup age, 5xx/429 rates, login failures, and deployment failures. The shared
host currently reports a failed global certbot renewal because unrelated stale
domains cannot renew; clean that up and alert per certificate.

### P1.6 Publish provenance and a security contact

The repository is public and MIT licensed, but the site does not link it, there
are no Git tags or GitHub Releases, no Actions workflows or `SECURITY.md`, and
`/.well-known/security.txt` returns 404. Tag release source, publish artifacts
and checksums, run CI checks and scans, link the source, and offer a private
vulnerability-reporting route. The privacy page now supplies a general privacy
contact; a dedicated security route is still needed.

### P1.7 Prove the clean two-person launch journey

Run the shipping DMG against a live-equivalent relay: clean install, registration,
repo selection, exact publish capture, second user, invite and reciprocal feed,
Offline and stale presence, relaunch, device link/revoke, token loss, avatar
replacement, account deletion, update, and backup restore. Preserve screenshots
and HTTP assertions as release evidence.

## P2 — high-value polish after the safety floor

### P2.1 Make `make check` fail clearly on unsupported Node

The README supports Node 20, 22, or 24, but Node 26 produced 127 misleading test
failures from a native SQLite ABI mismatch. Pin a supported toolchain and add a
preflight with one clear remediation message.

### P2.2 Make the HTTP API discoverable to agents and self-hosters

Document authentication, schemas, limits, refusal codes, lifecycle, and curl
examples from one contract. Add contract tests proving the macOS client and HTTP
surface share semantics. Do not add an MCP surface until a concrete tool-shaped
journey requires one.

### P2.3 Keep the website's privacy language in one source of truth

The download and invite pages contain shorter privacy summaries. Audit them
against the full notice whenever collection or sharing changes, link to the
notice, and avoid absolute claims that can drift. Remove the currently blocked
Google Fonts requests because the design already calls for system fonts and the
request creates needless ambiguity about third-party web traffic.

## Launch checklist

- [x] Privacy notice matches the accepted data-sharing posture and names current
  defaults, recipients, third parties, retention, and deletion limitations.
- [ ] Supported OS; non-root service; private data permissions; intended ports.
- [ ] Encrypted off-host backup and recorded restore drill.
- [ ] Registration and retained writes have durable global/account bounds.
- [ ] SvelteKit denial-of-service advisory fixed and deployed.
- [ ] Invite codes are absent from new access logs.
- [ ] Server-authoritative presence/time behavior and strict card validation.
- [ ] Security contact, tagged source, CI, and source-to-release provenance.
- [ ] Clean two-person shipping-DMG journey and rollback drill recorded.

## Evidence gathered

- Repository source/config/tests and git history at commit `c77620a`, plus the
  subsequently audited 0.10.3 release commit `86c15a7`.
- `make client`: successful signed Debug build.
- Server on Node 22: 165/165 tests passing; Svelte checks and production build
  passing during the original audit.
- Shipping 0.10.3/build 23 DMG: checksum, disk-image verification, Gatekeeper,
  signature, hardened runtime, and stapling passed.
- Live relay/host: HTTPS headers, health/API behavior, systemd/nginx/SSH/firewall,
  open sockets, permissions, SQLite integrity/schema, logs, timers, certificates,
  and backup search.

The original live checks were read-only. No production service, firewall, SSH,
certificate, database, account, or logging configuration was changed.
