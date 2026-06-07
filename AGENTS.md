# AGENTS.md

This repo is set up for a fast hackathon build. Keep changes focused, privacy-aware, and easy for another contributor to pick up.

## Product Intent

Vibes is a private ambient presence app for small groups of coding friends. It should feel warm, low-stakes, and technically useful without becoming a productivity dashboard.

Core v1 flow:

1. A Mac user configures local Git repos.
2. The app scans aggregate daily activity.
3. The user adds an optional manual status.
4. The user chooses Broadcasting, Quiet, or Offline.
5. Friends see each other's latest status through the relay.

## Repo Map

- `client/`: SwiftUI macOS app.
- `server/`: SvelteKit relay (API + web signup) backed by SQLite.
- `assets/`: brand assets. `assets/icon.png` is the canonical app mark.
- `deploy/`: nginx and systemd config.
- `scripts/`: deployment helpers.
- `docs/plans/active/spec-v1.md`: current product plan.
- `docs/client-runbook.md`: client setup and build notes.
- `docs/server-runbook.md`: relay deployment notes.

## Implementation Priorities

Work in this order unless the user says otherwise:

1. Local Git stats scanner.
2. SwiftUI app shell with mock feed, manual status, and mode picker.
3. Relay API and SQLite schema.
4. Real client publish/feed integration.
5. Invite flow and friend relationships.
6. Menu bar companion and window polish.

## Privacy Constraints

Default shared payloads may include:

- handle and display name
- presence mode
- manual status
- derived vibe label
- aggregate daily stats
- last updated timestamp
- optional agent mix
- optional repo aliases

Default shared payloads must avoid:

- raw repo paths
- branch names
- commit messages
- filenames
- exact editor or window activity
- detailed process history
- raw agent transcripts

## Visual Style

Vibes takes visual inspiration from Teenage Engineering: spare, premium, and quiet. The same language applies to the SwiftUI client and the web signup pages.

Principles:

- Two-color base: a warm off-black and a warm off-white. Light and dark mode swap which one is background and which is foreground.
- One restrained accent, used rarely — a single highlight, never decoration. The per-vibe feed tints are the one place more color is allowed.
- Thin sans-serif type: light weights for display, regular for body. Inter or the system sans. Never a monospaced font except for actual code, and never for stats, numbers, or labels.
- Extremely conservative use of retro or display faces — at most an occasional wordmark, never body text.
- No emoji anywhere. Use SF Symbols (client) or simple line glyphs (web) when an icon is genuinely needed.
- Layout comes from spacing and alignment, not borders and shadows. Avoid borders, dividers, and drop shadows unless absolutely necessary; when a separation is unavoidable, prefer a hairline in a near-background tone over a heavy rule.
- Generous whitespace, tight type, calm density. Let emptiness do the work.

Tokens: the canonical web tokens live in `server/src/lib/styles/tokens.css`. The core palette is a warm off-black (`#1a1714`) and warm off-white (`#f2eee6`) with warm-neutral grays and a single burnt-orange accent (`#e0531f`). The SwiftUI client mirrors the same palette, type scale, and spacing scale so both surfaces feel identical; update the tokens file first and mirror from it.

## Client Conventions

- Use native SwiftUI for macOS.
- Keep the main interface a small desktop window.
- Prefer straightforward app state and service types over framework-heavy architecture until the product hardens.
- If adding dependencies, document why in the README or runbook.
- Keep the checked-in Xcode project buildable with `make client`.

## Server Conventions

- The relay is a SvelteKit app (adapter-node) with SQLite via better-sqlite3.
- Keep the relay dumb: identity, invites, friends, latest status, feed.
- Open SQLite through `openDb` (WAL + busy_timeout) and route multi-statement writes through `writeTx` (single-writer pattern). Do not open ad-hoc connections.
- Add schema changes as a new migration in `db.js`; never edit an applied one.
- Avoid public discovery and broad social graph behavior in v1.
- Add API docs or curl examples as routes become real.
- Do not commit secrets, tokens, database files, or production cert material.

## Validation

Before handing off changes, run the relevant checks:

```bash
make check
```

For client-only changes:

```bash
make client
```

For server-only changes:

```bash
make server-check
```

## Definition of Done

These requirements apply to sessions that change code (anything under `client/`, `server/`, `scripts/`, or build config). Docs-only sessions (such as edits confined to `docs/`, `README.md`, or `AGENTS.md`) are exempt. When a session touches code, satisfy all three before it ends. They are requirements, not suggestions.

1. **Tests pass.** Run the relevant checks (`make check`, or `make client` / `make server-check` for scoped changes) and confirm they pass. Do not end a session with failing or skipped tests. If a test genuinely cannot pass, leave it failing and say so explicitly rather than deleting, skipping, or hiding it.

2. **Independent review of every code commit.** Every commit that changes code gets an independent review with fresh eyes via a sub-agent (for example a `code-reviewer` sub-agent or `/code-review`), not the author re-reading their own diff. Incorporate the review's feedback before the session ends (follow-up commits are fine). If a review item is intentionally not addressed, record why.

3. **Proof it works.** Provide evidence the code actually runs, not just that it compiles. Use passing test output for non-visual changes, or a screenshot of the running app for UI changes. "Done" without test results or a screenshot is not done.

## Git

- Keep commits small and descriptive.
- Every code-changing commit must be independently reviewed by a sub-agent with feedback incorporated (see Definition of Done).
- Do not rewrite unrelated user changes.
- Keep generated build products out of git.
