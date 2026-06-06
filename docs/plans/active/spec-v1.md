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

Agent detection can be heuristic or manual in v1. Allow users to manually enable or disable agent labels and set repo-level defaults.

Possible future detection methods:

- process names
- known config/history directories
- terminal/session markers
- commit message hints
- user-provided mapping
- local agent transcript paths

For v1, manual configuration plus lightweight heuristics is enough.

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

Data can be stored in simple JSON or SQLite. For the one-day build, JSON config and lightweight local persistence are fine.

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

- Node.js 22+
- HTTP API
- SQLite database
- nginx reverse proxy
- systemd service
- deployed to `https://vibes.opentangle.com`

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
- generated public/private keypair if time allows
- relay account/token

Friendship should be mutual.

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
- optional agent percentages
- optional repo aliases

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
  "totals": {
    "commits": 7,
    "files_changed": 31,
    "insertions": 1248,
    "deletions": 402,
    "uncommitted_insertions": 184,
    "uncommitted_deletions": 22,
    "repos_touched": 4
  },
  "agents": {
    "codex": 0.65,
    "claude_code": 0.25,
    "grok_build": 0.1
  },
  "repo_aliases": ["Vibes", "Braid"],
  "spotify": {
    "enabled": true,
    "artist": "Boards of Canada",
    "track": "Dayvan Cowboy"
  },
  "updated_at": "2026-06-06T18:02:00Z"
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

Use a simple config file for v1.

Example:

```yaml
identity:
  handle: marcus
  display_name: Marcus
tracking:
  repos:
    - path: ~/code/vibes
      alias: Vibes
      publish_alias: true
    - path: ~/code/braid
      alias: Braid
      publish_alias: true
agents:
  codex:
    enabled: true
    detection: auto
  claude_code:
    enabled: true
    detection: auto
  grok_build:
    enabled: true
    detection: manual
  gemini:
    enabled: true
    detection: manual
privacy:
  publish_repo_aliases: true
  publish_agent_mix: true
  publish_spotify: false
  publish_commit_messages: false
  publish_branch_names: false
  publish_file_names: false
server:
  relay_url: https://vibes.opentangle.com
```

## Agentic Configuration

The project should be friendly to agent-assisted setup. Users should ideally be guided by an agent or wizard.

The app or agent should help answer:

- Which repos should be tracked?
- Should repo names be published or hidden?
- Which coding agents do you use?
- Should Spotify be included?
- Should work repos be excluded?
- What handle/display name should friends see?
- What relay should be used?

For v1, a simple guided setup or generated config file is enough.

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
- App Store distribution
- perfect agent attribution

## One-Day Execution Plan

### Phase 1: Local Scanner

Build a local scanner that reads configured repo paths and produces aggregate daily JSON.

This can initially be a Swift service or a separate helper command.

### Phase 2: Local UI

Build the small SwiftUI window:

- friend rows using mock data
- own status editor
- mode toggle
- scan-now button
- simple settings/config

### Phase 3: Relay

Build minimal API:

- `POST /api/status`
- `GET /api/feed`
- `POST /api/invites`
- `POST /api/invites/accept`

Use simple auth/token for v1.

### Phase 4: Real Friend Feed

Connect two running clients through the relay.

Goal: Marcus and Ken can see each other's status update.

### Phase 5: Polish

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
