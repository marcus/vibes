# AGENTS.md

This repo is set up for a fast hackathon build. Keep changes focused, privacy-aware, and easy for another contributor to pick up.

## Product Intent

Vibes is a private ambient presence app for small groups of coding friends. It should feel warm, low-stakes, and technically useful without becoming a productivity dashboard.

Core v1 flow:

1. A Mac user configures local Git repos.
2. The app scans aggregate daily activity.
3. The user adds an optional manual status.
4. Presence is automatic — online while recently active, with a one-tap Offline toggle to hide.
5. Friends see each other's latest status through the relay.

## Repo Map

- `client/`: SwiftUI macOS app.
- `server/`: SvelteKit relay (API + web signup) backed by SQLite.
- `assets/`: brand assets. `assets/icon.png` is the canonical app mark.
- `deploy/`: nginx and systemd config.
- `scripts/`: deployment helpers.
- `docs/plans/active/spec-v2.md`: current product plan.
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
- optional repo aliases

Default shared payloads must avoid:

- raw repo paths
- branch names
- commit messages
- filenames
- exact editor or window activity
- detailed process history
- raw agent/tool transcripts
- coding-tool, editor, assistant, or human-vs-AI attribution

## Visual Style

Vibes has moved away from the original Teenage Engineering reference and now follows a clean native macOS glass direction: soft layered surfaces, system typography, restrained contrast, rounded controls, subtle depth, and quiet status color. The SwiftUI client is the highest-fidelity expression of this style. The web admin and future Tauri client should use the same macOS-like tokens by default, with Windows and Linux extensions layered on top for the cross-platform app.

Principles:

- Default to a calm macOS-glass feel: near-white/light surfaces, dark-mode equivalents, gentle translucency where reliable, and solid fallbacks everywhere.
- Use restrained accent and status color. Primary, destructive, and presence states should be clear but not loud; avoid decorative color.
- Use system sans typography. Never use a monospaced font except for actual code, ids, tokens, and diagnostics.
- Keep controls rounded, soft, and native-feeling without pretending web UI is real SwiftUI/WinUI/GTK.
- No emoji anywhere. Use SF Symbols in the native client and simple line glyphs or icon components on web/Tauri when an icon is genuinely needed.
- Layout comes from spacing, alignment, and subtle depth. Avoid heavy borders, dividers, and drop shadows; when separation is unavoidable, use quiet hairlines or soft surface contrast.
- Admin and app surfaces should stay dense and practical: no marketing-page heroes, decorative gradients, or ornamental glass effects inside operator/product UI.

Tokens: the canonical web/admin tokens live in `server/src/lib/styles/tokens.css`, with admin extensions in `server/src/lib/styles/admin.css`. Update those toward the macOS-glass defaults first, then add narrow Windows/Linux token extensions for the Tauri app rather than building separate UIs for each OS.

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
- When work is complete and validated, commit the finished changes before handing off unless the user explicitly asks you not to commit.
- Do not rewrite unrelated user changes.
- Keep generated build products out of git.
