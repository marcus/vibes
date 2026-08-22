# Vibes: Server Admin Plan v1

Status: implemented (moved from active 2026-08-21).

## Purpose

The relay can create users, invites, tokens, statuses, and friendships through the API and a small CLI, but there is no way to *operate* it from a browser: no way to see who exists, watch open invites, hand someone an initial invite link, or clean up a bad account. This plan adds a password-gated admin area to the SvelteKit relay for a single superuser, plus the session plumbing it needs.

This is a server-side plan only. It does not change the macOS client or the public `/invite/<code>` signup flow.

## Goals

- A superuser can log into a web admin area protected by a password.
- List and manage users: view, disable/enable, delete, and inspect each user's devices, tokens, invites, friends, and current presence.
- Create a user and mint an initial invite link (the bootstrap path: "get me a first invite token").
- See all invites across the relay, filter by state, create and revoke them.
- Full superuser control, applied across every user (not scoped to one owner like the API is).

## Non-Goals (v1)

- Self-serve user accounts on the web. The data layer is built so a future `/me` page can reuse it, but no user-facing login ships now.
- Multiple admins or per-admin attribution. The superuser is whoever holds the admin password.
- Email, password reset flows, or 2FA.
- Editing status payloads or impersonating users.

## Decisions

- **Auth: admin password → signed cookie session.** A long random secret is configured via the `VIBES_ADMIN_PASSWORD` environment variable. `/admin/login` exchanges it for a session. Sessions are stored in SQLite (revocable, visible) and referenced by an httpOnly cookie holding a random token; only the token hash is stored.
- **User management is admin-rendered.** The superuser manages users from per-user detail pages inside `/admin`. There is no self-serve user login in v1.
- **Leave a path to self-serve.** The `sessions` table carries a `kind` (`admin` | `user`) and nullable `user_id` so a future token-login `/me` page can reuse the same machinery. The owner-scoped relay functions (`listInvites`, `createInvite`, `revokeInvite`, `revokeToken` keyed by `user_id`) already fit a self-serve user managing their own invites.
- **Superuser identity is the password, not a user row.** No `is_admin` column is needed for v1. A per-user admin role can be added later when token-login admins or self-serve users arrive.

## Auth and Session Model

### Admin password

- `VIBES_ADMIN_PASSWORD` is read at runtime. If it is unset or empty, the admin area is disabled: `/admin/*` returns 404 so an un-configured relay exposes no login surface.
- Login compares the submitted password to the env value in constant time (`crypto.timingSafeEqual` on equal-length buffers). `/admin/login` is rate limited per IP via the existing `checkRateLimit`.
- The password lives in the systemd unit's `Environment=` (root-readable only). Rotating it means editing the env and restarting; existing sessions are unaffected until they expire or are cleared.

### Sessions table (new migration)

```sql
CREATE TABLE sessions (
  id TEXT PRIMARY KEY,
  token_hash TEXT NOT NULL UNIQUE,
  kind TEXT NOT NULL,                 -- 'admin' for v1; 'user' reserved for self-serve
  user_id TEXT REFERENCES users(id) ON DELETE CASCADE,
  created_at TEXT NOT NULL,
  last_seen_at TEXT,
  expires_at TEXT NOT NULL
);
```

- On successful login the relay generates a random session token, stores its SHA-256 hash, and sets a cookie: `httpOnly`, `Secure`, `SameSite=Lax`, `Path=/admin`, with a max age.
- Lifetime: absolute expiry (e.g. 7 days) plus idle timeout (e.g. 12 hours of no activity) refreshed on each request via `last_seen_at`. Expired rows are ignored and lazily deleted.
- Logout deletes the session row and clears the cookie.
- Raw tokens are never logged or stored, consistent with how bearer tokens and invite codes are handled.

### Route guard

- A `/admin` layout server load resolves the session cookie to a live, unexpired `admin` session. No session → redirect to `/admin/login`. Login and the static error page are the only unauthenticated `/admin` routes.
- SvelteKit's built-in form-action CSRF check plus the deployed `ORIGIN` env already cover POST protection; the same applies to admin form actions.

## Data Layer

A new `server/src/lib/server/admin.js` holds cross-user queries and superuser mutations, reusing relay primitives where they exist. It is the only module that reaches across user boundaries; the existing owner-scoped functions in `relay.js` stay untouched so they remain safe for a future `/me`.

Reads:

- `listUsers(db, { search, sort })` — handle, display name, created_at, disabled_at, device/token/friend counts, current presence mode (derived from `getFeed`/merge or a lighter per-user status read).
- `getUserDetail(db, userId)` — profile, per-device status rows (label, mode, client_day, updated_at, server_received_at), tokens (label, created, last_used, revoked), invites created (via `listInvites`), friends, accepted-invite origin.
- `listAllInvites(db, { state })` — every invite with creator handle, accepted_by handle, state, created/expires; supports the "see open invites" view.
- `dashboardStats(db)` — counts of users, active tokens, invites by state, and how many users are currently broadcasting/quiet/offline.

Mutations (superuser, full control):

- `setUserDisabled(db, userId, disabled)` — toggles `disabled_at`. A disabled user's tokens already fail `authenticateToken` (it checks `users.disabled_at IS NULL`), so disabling immediately blocks publish/feed without deleting data.
- `deleteUser(db, userId)` — in one `writeTx`: null out `invites.accepted_by_user_id` for this user (that column has no cascade), then `DELETE FROM users`, which cascades tokens, friendships, created invites, and statuses. Hard delete; gated behind a typed confirmation in the UI.
- `adminCreateInviteFor(db, userId)` — wraps `createInvite`; returns the one-time link.
- `adminRevokeInvite(db, inviteId)` — like `revokeInvite` but without the creator check.
- `adminCreateToken(db, userId, label)` / `adminRevokeToken(db, tokenId)` — wrap `createToken` / a non-owner-scoped revoke; the raw token is shown once.
- `adminRemoveFriendship(db, userId, friendUserId)` — reuse `removeFriend` semantics by id.
- `createUser` is reused directly for "create a user".

### Schema notes

- The only required migration is `sessions`. Append it as migration version 2 in `db.js` (never edit version 1).
- `deleteUser` handles the `accepted_by_user_id` foreign key in application code, avoiding a SQLite table rebuild. If hard deletes become common, a later migration can rebuild `invites` with `ON DELETE SET NULL`.
- Optional `admin_audit` table (recommended, can land in the same migration): `(id, action, target_type, target_id, detail, created_at)` written on every mutation. With a single shared password there is no per-admin identity, but an action log is still useful for "what changed and when".

## Routes and Pages

All under `/admin`, server-rendered SvelteKit pages with form actions for mutations.

- `GET /admin/login` + login action — password form; on success set session cookie and redirect to `/admin`.
- `POST /admin/logout` — clear session.
- `/admin` — dashboard: headline counts, currently-broadcasting list, recent invites, quick links.
- `/admin/users` — searchable/sortable user table. Row → detail.
- `/admin/users/[id]` — the per-user manage page: profile; presence and devices; tokens (mint/revoke); invites (create/revoke, with one-time link reveal); friends (remove); disable/enable; delete (typed confirm).
- `/admin/invites` — global invite list with a state filter (open/accepted/expired/revoked), create-invite (pick a creator), and revoke.
- `/admin/users/new` — create a user, with an option to immediately mint an invite link.

One-time secrets (new tokens, invite links) are revealed exactly once in the action response and never re-rendered, matching the public accept page's token handling.

## Bootstrap: getting the first invite token

1. Set `VIBES_ADMIN_PASSWORD` to a long random value in the systemd unit (or `.env.deploy`) and restart the relay.
2. Open `/admin/login` and sign in.
3. `/admin/users/new` → create your own user (handle + display name), choosing "mint invite link".
4. Copy the one-time `/invite/<code>` link, open it, and accept it in the Mac app to receive your bearer token.

The existing CLI remains a fallback for a headless bootstrap (`users create`, `invites create`); the admin UI is the primary path once the password is set.

## Design

The admin should move away from the original Teenage Engineering token system and follow the current native macOS glass direction used by the app: soft layered surfaces, system typography, restrained contrast, rounded controls, subtle depth, and quiet status color. It is primarily an operator tool for the maintainer, so the default admin styling can be Mac-biased rather than trying to look equally native on every operating system.

Update `server/src/lib/styles/tokens.css` and `server/src/lib/styles/admin.css` so the canonical web/admin defaults feel closer to the current Mac client:

- soft white/near-white light-mode surfaces with dark-mode equivalents
- translucent panels where browser support is reliable
- solid fallbacks for every glass or backdrop treatment
- subtle blur/backdrop usage, not decorative haze
- quiet shadows only when they help establish depth
- rounded fields, buttons, pills, modals, and table containers
- system sans typography; monospace only for tokens, ids, and code
- presence/status color used sparingly
- clear but restrained primary and destructive states

The admin should stay dense and practical: tables, filters, and mutation forms should remain easy to scan and operate. Avoid marketing-page composition, oversized hero treatment, decorative gradients, and ornamental glass effects.

Future Windows/Linux token extensions belong to the Tauri app's platform layer. The server admin may continue using the Mac-like default tokens because it is not the public cross-platform client.

## Security

- Admin area is invisible and 404 when no password is configured.
- Constant-time password comparison; per-IP rate limit on login.
- Session cookie is httpOnly, Secure, SameSite=Lax, scoped to `/admin`, random and DB-backed for revocation; only the hash is stored.
- No secret (password, token hash, code hash) is ever rendered or logged. New tokens/invite links are shown once.
- Destructive actions (delete user) require a typed confirmation and are logged to `admin_audit` if enabled.
- Reuses the app-owned CSP and the `ORIGIN`-based CSRF protection already in place.

## Testing (Definition of Done when built)

- Unit tests for `admin.js`: `listUsers`/`getUserDetail` shapes, `deleteUser` cascade including the `accepted_by_user_id` null-out, disable blocks auth, cross-user invite/token revoke.
- Session tests: wrong password rejected, valid password issues a session, expired/cleared session is rejected, missing `VIBES_ADMIN_PASSWORD` disables the area (404).
- Route guard test: unauthenticated `/admin` redirects to login.
- Proof: screenshots of the dashboard, user list, user detail, and invites pages in both light and dark.

## Phasing

1. **Session + auth plumbing.** `sessions` migration, `VIBES_ADMIN_PASSWORD`, login/logout, `/admin` guard, rate limit.
2. **Read surfaces.** Dashboard, users list, invites overview, user detail (read-only).
3. **Mutations.** Create user, mint/revoke tokens, create/revoke invites, disable/enable, delete user; one-time secret reveals; optional audit log.
4. **Polish + ops.** Empty/error states, light/dark pass, `admin_audit`, runbook + `.env.deploy.example` updates, deploy env wiring.

## Future: self-serve user pages

When wanted, add `/me`: a `kind='user'` session minted by token-login (paste the bearer token or a signed self-link) reusing the `sessions` table and guard. The owner-scoped relay functions already support a user managing their own invites, tokens, friends, and status, so `/me` is mostly new routes over existing data functions — no rework of the admin layer.
