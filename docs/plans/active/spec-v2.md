# Vibes: Product Spec v2

Supersedes `docs/plans/deprecated/spec-v1.md`. This version removes code-origin / agent attribution from the product model while keeping aggregate local Git stats as the core shared signal.

## Concept

Vibes is a small macOS desktop app for private, ambient presence among coding friends. It shows who is around, what kind of building day they are having, and lightweight stats from configured local repos.

The core feeling:

```text
Who is around and building something today?
```

Vibes is a fun private presence layer for small friend groups who hack on projects together. It should make people smile when they see their friends building things.

## Target

Build a one-day hackathon-quality prototype that can plausibly become a real small app.

Primary target:

- macOS
- Native SwiftUI
- Small mostly chromeless desktop app
- Optional menu bar companion
- Tiny centralized VPS relay
- Local Git repo stats scanner
- Manual status text
- Broadcast / quiet / offline control
- Friend feed

Assume users are technical Mac users.

## Product Shape

The main UI is a small desktop window. It should feel like a lightweight floating panel or desktop buddy window:

- small
- mostly chromeless
- remembers position
- visually calm
- easy to leave open
- easy to hide

The menu bar companion is secondary.

Menu bar actions:

- Show / Hide Vibes
- Set Broadcasting / Quiet / Offline
- Scan now
- Quit

## Presence States

### Broadcasting

Friends can see current derived stats and manual status.

Example:

```text
Marcus is vibing
4 repos touched - 7 commits - +1,248 / -402 LOC
"working on Vibes"
```

### Quiet

User is online but not broadcasting details.

Example:

```text
Marcus is online, not broadcasting
```

Quiet should publish a latest status with `mode: "quiet"` and no share cards. It should not preserve old broadcast cards in the feed while hiding them client-side.

### Offline / Invisible

Friends see user as offline or last seen, depending on implementation.

Example:

```text
Marcus offline - last seen 2h ago
```

Quitting the app should not be the only privacy control.

## Manual Status

Users can type a short custom status, similar to Slack or Discord presence.

Examples:

- "working on Vibes"
- "debugging SwiftUI window nonsense"
- "deep work"
- "coffee then shipping"
- "not coding, just around"

Manual status is separate from derived status. Derived status can say "vibing" or "deep work"; manual status is user-authored.

Manual status should be optional and easy to clear.

## Derived Vibes

The app can derive a coarse status from local activity.

Initial statuses:

- offline
- quiet
- warming up
- vibing
- deep work
- yak shaving
- ship mode
- wandering
- rage fixing

Initial derivation can be simple:

- no activity recently: quiet / offline
- small activity: warming up
- multiple commits or uncommitted changes: vibing
- sustained repo activity: deep work
- many repos touched: wandering or yak shaving
- many deletions or refactors: yak shaving
- recent commits with substantial changes: ship mode

Exact heuristics are not critical for v1.

## Local Git Stats

The local app scans configured Git repositories.

Track per day:

- commits
- files changed
- insertions
- deletions
- repos touched
- uncommitted insertions/deletions
- latest activity timestamp
- optional repo aliases

Use the user's local calendar day for "today" rather than a rolling 24-hour window. When the local day rolls over, the client rescans and republishes so the feed resets to the new day's stats; until it republishes, the previous `client_day` blob stays visible and the feed treats it as belonging to that earlier day. The scanner should not count untracked files in v1; use committed changes, working tree diff, and staged diff only.

Use local Git CLI commands rather than GitHub APIs.

Useful commands:

```bash
git log --since=midnight --numstat --pretty=format:
git diff --numstat
git diff --cached --numstat
```

Stats should be aggregated locally before publishing.

Default shared payload should avoid sensitive details such as branch names, commit messages, file names, raw repo paths, and private repo names. Repo aliases may be user-configured and opt-in.

## Code-Origin Attribution

Vibes should not track, infer, configure, publish, or display how code was produced. Do not add agent lists, editor lists, per-repo coding-tool labels, process detection, transcript scanning, commit-message attribution, or "human vs AI" summaries.

The product signal is intentionally narrower: aggregate daily Git stats from explicitly configured local repositories, plus optional repo aliases. Spotify and weather can remain future optional cards, but they are separate ambient context and not code-origin attribution.

## Spotify Stretch Goal

Optional: show currently playing Spotify track.

Possible approaches:

- AppleScript / local automation if Spotify desktop app is running
- Spotify Web API OAuth later

For hackathon v1, prefer local detection if simple. Keep Spotify off by default.

Shared display example:

```text
listening to Boards of Canada - Dayvan Cowboy
```

## Architecture

Use a native SwiftUI macOS app plus a small centralized relay service.

### Client

SwiftUI macOS app:

- small main desktop window
- optional chromeless/floating polish
- optional menu bar companion
- local config
- local Git scanner
- local status aggregation
- broadcast mode toggle
- manual status editor
- friend feed UI, including an empty state when the user has no friends yet
- friend detail popover
- invite sheet for creating, sharing, and revoking invites
- minimal settings window for repos, sharing, and identity
- periodic scan/publish
- secondary manual refresh action for debugging or impatient users

The app will not target the Mac App Store. V1 can be signed for local distribution without App Store sandboxing. This keeps arbitrary local repo scanning straightforward and avoids security-scoped bookmark work during the hackathon.

Use JSON config and lightweight local persistence for the first build. If local persistence grows beyond simple settings and cached feed state, SQLite is fine.

### Relay

Tiny VPS-hosted API.

Responsibilities:

- user identity
- friend invites
- friend relationships
- latest status blobs
- feed endpoint

The relay should store latest presence/status data and serve friend feeds. Use SQLite for the first version.

Initial stack:

- Node.js 20+
- HTTP API
- SQLite database
- nginx reverse proxy
- systemd service
- deployed to a configurable HTTPS relay host

### Status Semantics

The relay stores the latest status only. It does not store status history by default.

Status records do not expire. If a user has ever published a status, friends can continue to see that latest status with its `updated_at` timestamp. The client can render stale states such as "last updated 3h ago" or "last updated yesterday", but the relay should not delete or hide a status just because it is old.

Offline is an explicit presence mode or the absence of any status. On a graceful quit the app makes a best-effort publish of an Offline status for that device. If the app exits without publishing Offline, the previous status remains visible as stale.

Quiet is also explicit. Publishing Quiet replaces the user's latest status blob with a quiet payload containing no optional cards.

The model answers "what was their latest vibe?" rather than acting as a strict realtime online indicator.

### Multi-Device

A user can run Vibes on more than one Mac (for example a laptop and a desktop). Each install has its own device identity and its own auth token, and publishes its own status row keyed by `(user_id, device_id)`.

Each install generates a stable `device_id` (a local UUID) on first launch and stores it in config, along with a human `device_label` such as "MacBook" or "Mac mini". The client sends both with every `POST /api/status`.

The feed merges a user's device rows into one presence view per user on read. Merge rules:

- Presence mode is the strongest mode across the user's devices, using the order broadcasting > quiet > offline. A user is Offline only when every device is Offline or absent.
- Manual status, derived vibe, and singleton cards (`spotify`, `weather`, `repo_aliases`) come from the broadcasting device with the most recent `updated_at`.
- `git_stats` is summed across broadcasting devices that share the most recent `client_day`. Devices reporting an older `client_day` are ignored so a stale laptop does not inflate today's totals.
- `updated_at` for the merged view is the newest contributing device's `updated_at`.

Revoking a device's token stops that device from publishing. Its last status row remains until overwritten or until the row is removed by admin action.

### Status Blob Extensibility

The latest status blob is the central primitive. It should have a stable core plus typed optional cards.

Core fields:

- user identity summary
- presence mode
- manual status
- derived vibe label
- client day
- `updated_at`

Optional cards can represent things the user chooses to share:

- `git_stats`
- `repo_aliases`
- `spotify`
- `weather`
- future adapter-defined cards

Each card should include:

- `type`: stable card type string
- `enabled`: whether the card is intended to be shared
- `summary`: short display-friendly text when useful
- `data`: card-specific JSON payload

Adapters can produce cards locally. The publish layer decides which enabled cards enter the final status blob based on privacy config. The relay should treat cards as JSON and avoid interpreting card-specific details except for basic validation and size limits.

Status payloads should be capped at 32 KB for v1. If a client receives an unknown card type, it should render the card's `summary` when present. If no usable summary exists, hide the card but show a small UI affordance indicating that one unsupported/hidden card exists, so the user can distinguish intentional hiding from a feed error.

### Relay Data Model

Use SQLite with a deliberately small schema. The relay is flexible enough to evolve, and the v1 tables are concrete so auth, invites, and feed reads are not improvised.

v1 tables:

```sql
CREATE TABLE users (
  id TEXT PRIMARY KEY,
  handle TEXT NOT NULL UNIQUE,
  display_name TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  disabled_at TEXT
);

CREATE TABLE auth_tokens (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token_hash TEXT NOT NULL UNIQUE,
  label TEXT,
  created_at TEXT NOT NULL,
  last_used_at TEXT,
  revoked_at TEXT
);

CREATE TABLE friendships (
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  friend_user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  state TEXT NOT NULL DEFAULT 'accepted',
  created_at TEXT NOT NULL,
  PRIMARY KEY (user_id, friend_user_id)
);

CREATE TABLE invites (
  id TEXT PRIMARY KEY,
  code_hash TEXT NOT NULL UNIQUE,
  creator_user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  accepted_by_user_id TEXT REFERENCES users(id),
  created_at TEXT NOT NULL,
  accepted_at TEXT,
  revoked_at TEXT,
  expires_at TEXT
);

CREATE TABLE statuses (
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  device_id TEXT NOT NULL,
  device_label TEXT,
  mode TEXT NOT NULL,
  client_day TEXT NOT NULL,
  payload_json TEXT NOT NULL,
  schema_version INTEGER NOT NULL DEFAULT 1,
  updated_at TEXT NOT NULL,
  server_received_at TEXT NOT NULL,
  PRIMARY KEY (user_id, device_id)
);

CREATE TABLE schema_migrations (
  version INTEGER PRIMARY KEY,
  applied_at TEXT NOT NULL
);
```

Notes:

- `statuses` is one row per `(user_id, device_id)`. `POST /api/status` upserts on that key. See Multi-Device for how the feed merges a user's devices.
- `updated_at` comes from the client payload; `server_received_at` is when the relay accepted it.
- `client_day` allows local-day stats without making the relay understand user time zones.
- `payload_json` stores the publishable status blob, not raw scanner output.
- `friendships` stores reciprocal rows for v1. Feed queries stay simple and direct. Unfriending deletes both rows.
- `expires_at` on invites is allowed because invite lifetime is different from status lifetime.
- The raw invite code is never stored. Only `code_hash` is persisted; the usable `/invite/<code>` URL is returned once at creation time, so a database read cannot recover live codes.
- Handles are stored lowercased so uniqueness is case-insensitive.
- `schema_migrations` records applied migration versions. Migrations are a versioned list applied in one IMMEDIATE transaction; add one by appending a new version, never by editing an applied one. `db migrate` is idempotent and safe to run while the relay is up.
- The relay opens SQLite with WAL, `busy_timeout`, and `synchronous = NORMAL`, and routes multi-statement writes through IMMEDIATE transactions (single-writer pattern). Reads stay concurrent; a second writer such as the CLI waits for the lock rather than failing.

### Auth Model

Use bearer tokens for v1.

- The client sends `Authorization: Bearer <token>` for all authenticated API calls.
- The relay stores only `token_hash`, never the raw token.
- Tokens can be created during setup, invite acceptance, or an admin/bootstrap flow.
- Tokens can be revoked by setting `revoked_at`.
- A token identifies exactly one user.
- Feed reads return the caller's own status plus accepted friends' latest statuses.

This leaves room for future signed status blobs or keypair identity without blocking the hackathon on a full auth system.

### API Contract

The relay and client share one contract. Every endpoint accepts and returns JSON, except `GET /invite/:code`, which returns HTML.

Authenticated endpoints require `Authorization: Bearer <token>`. A missing or revoked token returns `401`.

Errors use a single shape with an appropriate HTTP status:

```json
{ "error": { "code": "string_code", "message": "human readable" } }
```

Endpoints:

- `POST /api/users` — create a user during bootstrap.
  - Request: `{ "handle": "marcus", "display_name": "Marcus" }`
  - Response `201`: `{ "user": { "id": "...", "handle": "marcus", "display_name": "Marcus" } }`
  - `409 handle_taken` if the handle exists.
- `POST /api/invites` (auth) — create an invite for the caller.
  - Request: `{}`
  - Response `201`: `{ "id": "...", "invite_url": "https://relay/invite/<code>", "expires_at": "..." }`
- `GET /api/invites` (auth) — list the caller's invites.
  - Response `200`: `{ "invites": [ { "id": "...", "invite_url": "...", "state": "open|accepted|revoked|expired", "created_at": "...", "expires_at": "...", "accepted_by": "ken" } ] }`. `accepted_by` is null until an invite is accepted.
- `POST /api/invites/:id/revoke` (auth) — revoke an invite the caller created.
  - Response `200`: `{ "ok": true }`. Idempotent. `404` if the invite is not the caller's.
- `GET /invite/:code` — HTML accept page.
- `POST /invite/:code/accept` — accept an invite and create the accepting user.
  - Request: `{ "handle": "ken", "display_name": "Ken", "device_label": "Ken MacBook" }`
  - Response `201`: `{ "token": "<raw token shown once>", "config": { ...first-launch config JSON... } }`
  - `409 handle_taken` if the handle exists; the caller may retry with a different handle. The invite is consumed only on success.
  - `410 invite_unusable` if the invite is expired, revoked, or already used.
- `POST /api/status` (auth) — upsert the caller's status for one device.
  - Request: the status blob plus `device_id` and `device_label`.
  - Response `200`: `{ "ok": true, "server_received_at": "..." }`
  - `413 payload_too_large` if the blob exceeds 32 KB.
- `GET /api/feed` (auth) — the caller's own merged status plus accepted friends' merged statuses.
  - Response `200`: `{ "you": { ...merged status... }, "friends": [ { ...merged status... } ] }`
- `POST /api/friends/remove` (auth) — unfriend a user by handle.
  - Request: `{ "handle": "ken" }`
  - Response `200`: `{ "ok": true }`. Deletes both reciprocal `friendships` rows. Idempotent.
- `POST /api/tokens/revoke` (auth) — revoke a token the caller owns.
  - Request: `{ "token_id": "..." }`
  - Response `200`: `{ "ok": true }`

Public endpoints (`POST /api/users`, `GET /invite/:code`, `POST /invite/:code/accept`) and `POST /api/status` are rate limited per IP. The limit is coarse and only needs to stop accidental loops and casual abuse for v1.

#### Keeping client and relay in sync

The contract has one source of truth so the Swift client and Node relay cannot drift:

- Canonical request/response/error examples live as JSON fixtures in `shared/contract/` in the repo. The example status blob, feed response, and error shape are fixtures, not prose.
- The relay has a contract test that exercises each endpoint and asserts responses match the fixtures.
- The client has a decode test that loads the same fixtures into its `Codable` models.
- Both test suites read the same files, so a contract change that breaks either side fails CI before it ships. Changing an endpoint means changing the fixture, which forces both sides to update.

### Magic-Link Invites

Friend setup uses a magic-link style flow. An invite is 1:1: it is single-use and connects exactly the creator and the one friend who accepts it. A group of friends connects through one invite per pair.

Invite flow:

1. Existing user asks the relay to create an invite.
2. Relay returns a URL like `https://relay.example.com/invite/<code>`.
3. The raw invite code is shown only in the URL. The relay stores `code_hash`.
4. Friend opens the link.
5. The relay returns a tiny web page that asks for handle/display name if needed.
6. Accepting the invite can create the accepting user for v1.
7. Accepting the invite creates the accepting user's token and creates a mutual friendship.
8. The browser shows the raw token exactly once and also offers a downloadable config JSON snippet. Later this can become a custom URL scheme.
9. On first launch, the app can import the downloaded config JSON, accept a pasted config/token, or open a local config file selected by the user.

Invites are single-use, expire after 7 days, and are manually revocable. Accepting an invite never reveals the creator's token.

Raw invite codes and bearer tokens never appear in logs. The relay stores only `code_hash` and `token_hash`, and the application and reverse proxy are configured not to log the `/invite/<code>` path, the `Authorization` header, or accept-response bodies.

A minimal HTML response is enough for the accept page as long as the URL can be shared directly.

### First-Launch Setup

For non-developers, first launch should be a setup screen rather than an empty app.

The setup screen should support:

- importing a downloaded invite/config JSON file
- pasting a relay URL plus one-time token
- opening an existing config from `~/Library/Application Support/Vibes/config.json`

After import, the app should:

1. validate the relay URL and token with the relay
2. generate a `device.id` and `device.label` if the config does not already have one
3. write config JSON to Application Support
4. store the raw token in Keychain
5. remove the raw token from the persisted config if present
6. start automatic scan/publish/feed refresh

The app should not require the user to press "Scan Now" during normal operation.

## Federation / Distributed Future

Design as if status blobs could later be portable or federated, while keeping v1 centralized for onboarding and connectivity.

Future direction:

- signed portable status blobs
- multiple relays
- small federated friend graph

## Identity and Friend Graph

Users should have a local identity:

- handle
- display name
- relay account/token
- generated public/private keypair later if useful

Friendship is mutual. Either friend can unfriend the other, which removes both reciprocal rows and stops sharing in both directions.

Handles are globally unique per relay for v1.

Invite flow:

1. User creates invite link or code.
2. Friend opens or uses invite.
3. Friendship is accepted.
4. Both users can see each other's latest status.

V1 should support direct friends only.

Future graph model can support:

- direct friends
- private users
- discoverable-to-friends
- presence-only friend-of-friend visibility

## Privacy Defaults

Default shared status should include only:

- handle/display name
- presence state
- manual status if user entered one
- derived vibe label
- aggregate daily stats
- last updated timestamp
- optional enabled cards such as repo aliases, Spotify, or weather

Default shared status should avoid:

- repo paths
- branch names
- commit messages
- filenames
- exact editor/window activity
- detailed process history
- raw agent/tool transcripts
- code-origin attribution such as editor, assistant, agent, or human-vs-AI labels

The app is for friends, but still avoid accidental oversharing.

## Example Status Payload

```json
{
  "user": {
    "handle": "marcus",
    "display_name": "Marcus"
  },
  "mode": "broadcasting",
  "manual_status": "working on Vibes",
  "derived_status": "vibing",
  "day": "2026-06-06",
  "updated_at": "2026-06-06T18:02:00Z",
  "cards": [
    {
      "type": "git_stats",
      "enabled": true,
      "summary": "4 repos touched - 7 commits - +1,248 / -402 LOC",
      "data": {
        "commits": 7,
        "files_changed": 31,
        "insertions": 1248,
        "deletions": 402,
        "uncommitted_insertions": 184,
        "uncommitted_deletions": 22,
        "repos_touched": 4
      }
    },
    {
      "type": "repo_aliases",
      "enabled": true,
      "summary": "Vibes, Braid",
      "data": {
        "aliases": ["Vibes", "Braid"]
      }
    },
    {
      "type": "spotify",
      "enabled": true,
      "summary": "Boards of Canada - Dayvan Cowboy",
      "data": {
        "artist": "Boards of Canada",
        "track": "Dayvan Cowboy"
      }
    }
  ]
}
```

## Example UI

Main panel:

```text
+------------------------------------+
| Vibes                              |
|                                    |
| Marcus      vibing        +1.2k    |
| "working on Vibes"                 |
|                                    |
| Ken         deep work       +412   |
| "refactoring the weird part"       |
|                                    |
| Justin      quiet            -     |
| online, not broadcasting           |
|                                    |
| Status: working on Vibes           |
| Mode: Broadcasting v               |
+------------------------------------+
```

User detail view:

```text
Ken today
Status: deep work
Manual: "refactoring the weird part"
Commits: 5
Files touched: 18
Repos: garden-sim, taxbot-ui
Last update: 8m ago
```

## macOS UX

### Window and Activation Model

Vibes is a regular Dock app (`.regular` activation policy) with one main window and a secondary menu bar companion. The menu bar companion provides quick mode switching and Show/Hide without bringing the app forward; it is not the only way to reach the app.

The main window is a standard, calm, resizable SwiftUI window with a minimal title bar. It has a small minimum size and remembers its position and size across launches via frame autosave. Closing the window hides it while the app keeps running, so presence keeps publishing; the user reopens it from the Dock icon or the menu bar's "Show Vibes". Quit is explicit (Cmd-Q or the menu bar Quit action) and triggers the best-effort Offline publish.

A fully chromeless or floating-panel presentation, an always-on-top toggle, and a global hotkey remain later polish and do not change this model.

### Layout and Navigation

The main window has three regions:

- A slim header with the app name and a sync indicator.
- A scrolling friend feed. Rows scroll when friends overflow the window height. The user's own row is not shown in the feed; their state lives in the footer.
- A footer with the user's own mode control and manual status field.

Clicking a friend row opens that friend's detail as a popover anchored to the row. The detail is read-only in v1 and shows the expanded stats and last-update time from the example detail view, plus a "Remove friend…" action that confirms before calling unfriend. Dismissing the popover returns to the feed.

### Own Status Controls

The footer holds two controls:

- A mode control (Broadcasting / Quiet / Offline). Changing it publishes immediately.
- A single-line manual status field. Typing and committing publishes the new manual status; clearing the field to empty removes `manual_status`. A small clear affordance empties it in one click.

### Settings Window

A standard Settings scene (Cmd-,) provides minimal in-app editing so non-developers are not forced into JSON:

- Repos: add a tracked repo with a folder picker, remove one, and per repo set its alias and publish-alias toggle. Because the app is not sandboxed, the folder picker needs no security-scoped bookmarks.
- Sharing: toggle each card in `sharing.cards` and each item in `sharing.redactions`.
- Identity and relay: show handle, display name, device label, and relay URL. These are mostly read-only in v1.

Settings writes the same config JSON described in Configuration, so hand-edited and setup-generated config stay interchangeable with what the UI produces.

### Visual Language

The app is native SwiftUI and supports both light and dark mode, following the system accent. The tone is calm and low-density: generous spacing, SF Pro text, and SF Symbols. Each derived vibe has an icon and tint so the feed reads at a glance. A starting mapping:

| Vibe | Symbol | Tint |
| --- | --- | --- |
| offline | `moon.zzz` | gray |
| quiet | `circle.dotted` | gray |
| warming up | `sunrise` | soft orange |
| vibing | `waveform` | green |
| deep work | `scope` | indigo |
| yak shaving | `scissors` | brown |
| ship mode | `paperplane.fill` | teal |
| wandering | `figure.walk` | purple |
| rage fixing | `flame` | red |

Exact symbols and tints are not critical for v1; the mapping exists so vibes are visually distinct rather than text-only.

### Brand Assets

The app mark lives at `assets/icon.png` (2048×2048). The client should use it as the macOS app icon — generate the `AppIcon` asset set (the standard macOS icon sizes) from this source — and may reuse the mark in the window header or wordmark. Do not restyle or recolor it; it is the canonical brand mark.

### Feed States

The feed has explicit states beyond the normal populated list:

- Loading: a subtle placeholder on first fetch before any feed data is cached.
- Stale: each friend row renders relative freshness such as "last updated 3h ago".
- Relay unreachable: a small inline banner ("Can't reach relay — showing last known") while the last cached feed stays visible.
- Empty: when the user has no friends yet, a friendly empty state with a "Create invite" action that opens the same invite flow described in Inviting Friends.

### Inviting Friends

Inviting is a primary action, not just an empty-state affordance, because growing the friend group is a core part of the experience. The main window header has an "Invite" button, and the menu bar companion has an "Invite a friend…" item. Both open the same invite sheet.

The invite sheet:

- A "Create invite link" button calls `POST /api/invites` and shows the returned single-use URL with a Copy button, a Share button using the macOS share sheet, and the expiry date.
- A list of the user's still-open invites (created, not yet accepted or expired), each with its expiry and a Revoke action that calls `POST /api/invites/:id/revoke`. Accepted, revoked, and expired invites drop off the list.

Because invites are 1:1, the sheet makes clear that each link connects exactly one friend, so onboarding a group means creating one link per person.

### Deferred

Accessibility polish (VoiceOver labels, Dynamic Type tuning), Launch at Login, notifications, and the chromeless/floating polish are deferred. The v1 window and controls should still use standard SwiftUI controls so basic accessibility comes for free.

## Configuration

Use a simple JSON config file for v1. Setup helpers may generate or edit this file, so human-friendly YAML is not required.

Store relay auth tokens in the macOS Keychain. The config file should reference the relay URL and local identity, but not store raw bearer tokens. If a hackathon build temporarily stores a token in config, keep that clearly marked as temporary and avoid committing local config files.

Default config location:

```text
~/Library/Application Support/Vibes/config.json
```

Keychain naming:

- service: `Vibes Relay`
- account: `<relay_url>|<handle>`

Example:

```json
{
  "identity": {
    "handle": "marcus",
    "display_name": "Marcus"
  },
  "device": {
    "id": "b9c1f3e2-7a4d-4f0c-9e21-5d2a8c6f1a90",
    "label": "MacBook"
  },
  "tracking": {
    "repos": [
      {
        "path": "~/code/vibes",
        "alias": "Vibes",
        "publish_alias": true
      },
      {
        "path": "~/code/braid",
        "alias": "Braid",
        "publish_alias": true
      }
    ]
  },
  "server": {
    "relay_url": "https://vibes.example.com"
  },
  "sharing": {
    "cards": {
      "git_stats": true,
      "repo_aliases": true,
      "spotify": false,
      "weather": false
    },
    "redactions": {
      "commit_messages": true,
      "branch_names": true,
      "file_names": true,
      "repo_paths": true
    }
  }
}
```

`sharing` is the single source of truth for what leaves the device. `sharing.cards` controls which optional cards are published: a card is included in the status blob only when its flag is true. `sharing.redactions` covers raw details that are never expressed as cards; `true` means that detail is redacted and never leaves the device. These redactions are belt-and-suspenders, since the default payload already excludes them.

## Guided Configuration

The project should be friendly to assisted setup. Users should ideally be guided by a setup helper or wizard.

The app or helper should answer:

- Which repos should be tracked? Repo tracking is explicit opt-in.
- Should repo names be published or hidden?
- Which optional cards should be shared?
- Should Spotify be included?
- Should weather be included?
- Should work repos be excluded?
- What handle/display name should friends see?
- What relay should be used?

For v1, a simple guided setup or generated config file is enough. Repo tracking should be explicit opt-in: the setup flow should ask which repos to track, write only those repos into config, and require later additions to be made deliberately.

## Relay CLI and Automation Interface

The relay should include a small CLI for bootstrap, admin, and scripted operations. Automation should use the CLI rather than editing SQLite directly.

Initial commands:

```bash
node server/cli.mjs db migrate
node server/cli.mjs users create --handle marcus --display-name Marcus
node server/cli.mjs tokens create --user marcus --label "Marcus MacBook"
node server/cli.mjs invites create --user marcus
node server/cli.mjs invites list --user marcus
node server/cli.mjs invites revoke --invite-id <id>
node server/cli.mjs invites accept --code <code> --handle ken --display-name Ken
node server/cli.mjs friends list --user marcus
node server/cli.mjs friends remove --user marcus --friend ken
node server/cli.mjs tokens revoke --token-id <id>
node server/cli.mjs status get --user marcus
```

The CLI should print machine-readable JSON by default or via `--json`, so automation can call it safely and parse results.

For v1, CLI output should be JSON by default. Human-friendly tables can come later if useful.

## Decision Notes

An ADR is an Architecture Decision Record: a short document that records one important technical/product decision, the alternatives considered, and the consequences. Vibes does not need heavy process. As implementation starts, each of these settled decisions gets a short ADR:

- latest-status-only relay, no status expiry
- bearer token auth for v1
- no Mac App Store sandbox target
- JSON config generated by setup helpers
- extensible status cards as the sharing model
- `sharing` config block as the single source of truth for what leaves the device
- per-device status rows merged into one presence view per user
- shared JSON fixtures as the client/relay contract

## Build Priorities

### Must Have

- SwiftUI macOS app
- small desktop window
- local repo config
- local Git stats scan
- manual status
- Broadcasting / Quiet / Offline mode
- relay publish
- friend feed
- at least basic invite/friend setup
- automatic scan/publish/feed refresh
- optional menu bar companion

### Should Have

- remember window position and size
- tune scan interval and stale-state display
- secondary manual refresh action
- clean visual design
- light and dark mode support
- derived vibe label with per-vibe iconography
- friend detail popover
- in-app invite creation, sharing, and revocation
- feed loading, stale, relay-unreachable, and empty states
- repo aliases
- privacy-respecting payload
- minimal settings window for repos, sharing, and identity

### Could Have

- mostly chromeless/floating panel
- always-on-top toggle
- global hotkey
- Spotify now playing
- signed status blobs
- Launch at Login
- notifications

### Later

- official WidgetKit widget
- peer-to-peer networking
- full federation
- public user discovery
- broad rankings
- GitHub OAuth
- chat
- mobile app
- notarized non-App-Store distribution

## One-Day Execution Plan

### Phase 1: Relay Schema and CLI

Build the SQLite schema, migration path, and relay CLI first.

Initial CLI capabilities:

- migrate database
- create users
- create/revoke tokens
- create/accept invites
- list friends
- inspect latest status

### Phase 2: Relay Auth and Invites

Build bearer token auth and the magic-link invite accept page.

### Phase 3: Status API

Build status publish and feed API:

- `POST /api/status`
- `GET /api/feed`

### Phase 4: Client Config and Keychain

Build Swift config loading and Keychain token storage.

### Phase 5: Local Scanner

Build a local scanner that reads configured repo paths and produces aggregate daily JSON.

This can initially be a Swift service or a separate helper command.

### Phase 6: Local UI

Build the small SwiftUI window:

- friend rows using mock data
- friend detail popover
- own status editor
- mode toggle
- automatic refresh loop
- secondary manual refresh action
- minimal settings window for repos, sharing, and identity

### Phase 7: Full Relay API

Complete the minimal API:

- `POST /api/status`
- `GET /api/feed`
- `POST /api/users`
- `POST /api/invites`
- `GET /api/invites`
- `POST /api/invites/:id/revoke`
- `POST /api/friends/remove`
- `POST /api/tokens/revoke`
- `GET /invite/:code`
- `POST /invite/:code/accept`

Use bearer token auth for v1.

### Phase 8: Real Friend Feed

Connect two running clients through the relay.

Goal: Marcus and Ken can see each other's status update.

### Phase 9: Polish

Add:

- menu bar companion
- window position persistence
- periodic scanning
- derived vibe label
- better visual design
- optional Spotify if time remains

## Success Criteria

By the end of the hackathon:

- Two people can run the app on their Macs.
- Each person can configure at least one repo.
- Each person can set a manual status.
- Each person can choose Broadcasting / Quiet / Offline.
- Each person can see the other person's current status and daily coding stats.
- The app feels like a small ambient friend-presence object.

## Product Tone

Vibes should feel warm, nerdy, low-stakes, and private.

Prefer language like:

- vibing
- around
- building
- quiet
- ship mode
- yak shaving
- what are friends up to?
