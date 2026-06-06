# Vibes: Product Spec v1

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

Use the user's local calendar day for "today" rather than a rolling 24-hour window. The scanner should not count untracked files in v1; use committed changes, working tree diff, and staged diff only.

Use local Git CLI commands rather than GitHub APIs.

Useful commands:

```bash
git log --since=midnight --numstat --pretty=format:
git diff --numstat
git diff --cached --numstat
```

Stats should be aggregated locally before publishing.

Default shared payload should avoid sensitive details such as branch names, commit messages, file names, raw repo paths, and private repo names. Repo aliases may be user-configured and opt-in.

## Agent Detection

Track coarse coding agent attribution where possible.

Initial supported agent labels:

- Codex
- Claude Code
- Gemini
- Grok Build
- Cursor
- Aider
- OpenCode
- Unknown / Manual / Human

V1 should use manual repo-level agent labels. Users or setup agents can assign a default agent label to each tracked repo, and the scanner can aggregate that into a coarse agent mix.

Automatic detection is future work. Allow users to manually enable or disable agent labels and set repo-level defaults.

Possible future detection methods:

- process names
- known config/history directories
- terminal/session markers
- commit message hints
- user-provided mapping
- local agent transcript paths

For v1, manual configuration is enough.

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
- friend feed UI
- periodic scan/publish
- scan-now action

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

Offline is an explicit presence mode or the absence of any status. If the app quits without publishing an Offline status, the previous status remains visible as stale.

Quiet is also explicit. Publishing Quiet replaces the user's latest status blob with a quiet payload containing no optional cards.

This keeps v1 simple and matches the desired product behavior: "what was their latest vibe?" rather than a strict realtime online indicator.

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
- `agent_mix`
- `repo_aliases`
- `spotify`
- `weather`
- `harness`
- future adapter-defined cards

Each card should include:

- `type`: stable card type string
- `enabled`: whether the card is intended to be shared
- `summary`: short display-friendly text when useful
- `data`: card-specific JSON payload

Adapters can produce cards locally. The publish layer decides which enabled cards enter the final status blob based on privacy config. The relay should treat cards as JSON and avoid interpreting card-specific details except for basic validation and size limits.

Status payloads should be capped at 32 KB for v1. If a client receives an unknown card type, it should render the card's `summary` when present. If no usable summary exists, hide the card but show a small UI affordance indicating that one unsupported/hidden card exists, so the user can distinguish intentional hiding from a feed error.

### Relay Data Model

Use SQLite with a deliberately small schema. The relay should be flexible enough to evolve, but the first version needs concrete tables so auth, invites, and feed reads are not improvised.

Suggested v1 tables:

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
  invite_url_path TEXT NOT NULL UNIQUE,
  accepted_by_user_id TEXT REFERENCES users(id),
  created_at TEXT NOT NULL,
  accepted_at TEXT,
  revoked_at TEXT,
  expires_at TEXT
);

CREATE TABLE statuses (
  user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  mode TEXT NOT NULL,
  client_day TEXT NOT NULL,
  payload_json TEXT NOT NULL,
  schema_version INTEGER NOT NULL DEFAULT 1,
  updated_at TEXT NOT NULL,
  server_received_at TEXT NOT NULL
);
```

Notes:

- `statuses` is one row per user. `POST /api/status` upserts this row.
- `updated_at` comes from the client payload; `server_received_at` is when the relay accepted it.
- `client_day` allows local-day stats without making the relay understand user time zones.
- `payload_json` stores the publishable status blob, not raw scanner output.
- `friendships` should store reciprocal rows for v1. Feed queries stay simple and direct.
- `expires_at` on invites is allowed because invite lifetime is different from status lifetime.
- `invite_url_path` is the public magic-link path, for example `/invite/<code>`.

### Auth Model

Use bearer tokens for v1.

- The client sends `Authorization: Bearer <token>` for all authenticated API calls.
- The relay stores only `token_hash`, never the raw token.
- Tokens can be created during setup, invite acceptance, or an admin/bootstrap flow.
- Tokens can be revoked by setting `revoked_at`.
- A token identifies exactly one user.
- Feed reads return the caller's own status plus accepted friends' latest statuses.

This leaves room for future signed status blobs or keypair identity without blocking the hackathon on a full auth system.

### Magic-Link Invites

Friend setup should use a magic-link style flow.

Recommended v1 flow:

1. Existing user asks the relay to create an invite.
2. Relay returns a URL like `https://relay.example.com/invite/<code>`.
3. The raw invite code is shown only in the URL. The relay stores `code_hash`.
4. Friend opens the link.
5. The relay returns a tiny web page that asks for handle/display name if needed.
6. Accepting the invite can create the accepting user for v1.
7. Accepting the invite creates the accepting user's token and creates a mutual friendship.
8. The browser shows the raw token exactly once and also offers a downloadable config JSON snippet. Later this can become a custom URL scheme.

Invites should be single-use by default, expire after 7 days, and be manually revocable. Accepting an invite should never reveal the creator's token.

For hackathon speed, a minimal HTML response is enough as long as the URL can be shared directly.

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

Friendship should be mutual.

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
- optional enabled cards such as agent percentages, repo aliases, Spotify, weather, or harness/tool info

Default shared status should avoid:

- repo paths
- branch names
- commit messages
- filenames
- exact editor/window activity
- detailed process history
- raw agent transcripts

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
      "type": "agent_mix",
      "enabled": true,
      "summary": "Codex 65%, Claude Code 25%, Grok Build 10%",
      "data": {
        "codex": 0.65,
        "claude_code": 0.25,
        "grok_build": 0.1
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
Agents: Claude Code 72%, Codex 28%
Last update: 8m ago
```

## Configuration

Use a simple JSON config file for v1. Setup agents are expected to generate or edit this file, so human-friendly YAML is not required.

Store relay auth tokens in the macOS Keychain. The config file should reference the relay URL and local identity, but not store raw bearer tokens. If a hackathon build temporarily stores a token in config, keep that clearly marked as temporary and avoid committing local config files.

Default config location:

```text
~/Library/Application Support/Vibes/config.json
```

Recommended Keychain naming:

- service: `Vibes Relay`
- account: `<relay_url>|<handle>`

Example:

```json
{
  "identity": {
    "handle": "marcus",
    "display_name": "Marcus"
  },
  "tracking": {
    "repos": [
      {
        "path": "~/code/vibes",
        "alias": "Vibes",
        "publish_alias": true,
        "agent": "codex"
      },
      {
        "path": "~/code/braid",
        "alias": "Braid",
        "publish_alias": true,
        "agent": "claude_code"
      }
    ]
  },
  "agents": {
    "codex": {
      "enabled": true
    },
    "claude_code": {
      "enabled": true
    },
    "grok_build": {
      "enabled": true
    },
    "gemini": {
      "enabled": true
    }
  },
  "privacy": {
    "publish_repo_aliases": true,
    "publish_agent_mix": true,
    "publish_spotify": false,
    "publish_commit_messages": false,
    "publish_branch_names": false,
    "publish_file_names": false
  },
  "server": {
    "relay_url": "https://vibes.example.com"
  },
  "sharing": {
    "cards": {
      "git_stats": true,
      "agent_mix": true,
      "repo_aliases": true,
      "spotify": false,
      "weather": false,
      "harness": false
    }
  }
}
```

## Agentic Configuration

The project should be friendly to agent-assisted setup. Users should ideally be guided by an agent or wizard.

The app or agent should help answer:

- Which repos should be tracked? Repo tracking is explicit opt-in.
- Should repo names be published or hidden?
- Which coding agents do you use?
- Which optional cards should be shared?
- Should Spotify be included?
- Should weather or local harness/tool info be included?
- Should work repos be excluded?
- What handle/display name should friends see?
- What relay should be used?

For v1, a simple guided setup or generated config file is enough. Repo tracking should be explicit opt-in: an agent should ask which repos to track during setup, write only those repos into config, and later additions should require the user to manually add the repo or ask an agent to add it.

## Relay CLI and Agent Interface

The relay should include a small CLI for bootstrap, admin, and agent-driven operations. Agents should use the CLI rather than editing SQLite directly.

Initial commands:

```bash
node server/cli.mjs db migrate
node server/cli.mjs users create --handle marcus --display-name Marcus
node server/cli.mjs tokens create --user marcus --label "Marcus MacBook"
node server/cli.mjs invites create --user marcus
node server/cli.mjs invites accept --code <code> --handle ken --display-name Ken
node server/cli.mjs friends list --user marcus
node server/cli.mjs tokens revoke --token-id <id>
node server/cli.mjs status get --user marcus
```

The CLI should print machine-readable JSON by default or via `--json`, so agents can call it safely and parse results.

For v1, CLI output should be JSON by default. Human-friendly tables can come later if useful.

## Decision Notes

An ADR is an Architecture Decision Record: a short document that records one important technical/product decision, the alternatives considered, and the consequences. Vibes does not need heavy process, but a few decisions should be written down once implementation starts so future agents do not reopen the same questions.

Good first ADRs:

- latest-status-only relay, no status expiry
- bearer token auth for v1
- no Mac App Store sandbox target
- JSON config generated by agents
- extensible status cards as the sharing model

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
- optional menu bar companion

### Should Have

- remember window position
- scan every few minutes
- scan-now button
- clean visual design
- derived vibe label
- repo aliases
- privacy-respecting payload
- local config editing

### Could Have

- mostly chromeless/floating panel
- always-on-top toggle
- global hotkey
- Spotify now playing
- signed status blobs
- richer agent detection
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
- perfect agent attribution

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
- own status editor
- mode toggle
- scan-now button
- simple settings/config

### Phase 7: Full Relay API

Complete the minimal API:

- `POST /api/status`
- `GET /api/feed`
- `POST /api/users`
- `POST /api/invites`
- `POST /api/invites/accept`
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
