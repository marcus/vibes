# Vibes: Presence Model & Copy Rework

Status: planning (not started). Captures intent and findings; refine before building.

## Purpose

Two related product changes:

1. **Rework presence.** Remove the "quiet" status entirely, move to an automatic recency-based signal ("online/green" if active recently, otherwise "last seen vibing N minutes ago"), and keep the fun status labels as a *flexible* list rather than hardcoded.
2. **Rewrite the website (and in-app) copy** to match what Vibes is actually for.

## Why remove "quiet"

"Quiet" was an "online but don't disturb" mode. But Vibes has no interruption mechanism — there is nothing to be disturbed by. The only planned social interaction is a subtle, opt-in acknowledgment ("wave"), not a message. So a do-not-disturb mode is meaningless. Presence should just reflect reality: are you active right now, and what's your vibe.

## Current behavior (reference)

### Presence modes (to change)
- Server: `MODES = {broadcasting, quiet, offline}`, `MODE_RANK` offline<quiet<broadcasting — [relay.js:7-8](server/src/lib/server/relay.js).
- Client: user-picked `PresenceMode` enum broadcasting/quiet/offline — [Models.swift:3-15](client/Vibes/Models.swift), menu in `MainPanel`.
- Detail text "online, not broadcasting" (quiet) vs "offline" — [ContentView.swift:263](client/Vibes/ContentView.swift).
- Admin tallies presence by these three — [admin.js:25-26,290-298](server/src/lib/server/admin.js), [admin/+page.svelte:60](server/src/routes/admin/+page.svelte).

### Derived "vibe" — the fun status (keep, but make flexible & drop "quiet")
- `deriveVibe` maps daily git stats → one of **"ship mode", "wandering", "yak shaving", "vibing", "warming up", "quiet"** — [GitScanner.swift:345-353](client/Vibes/GitScanner.swift). This list is exactly the "flexible status list" we want to keep; **"quiet" is the no-activity fallback to remove.**

### Multi-device aggregation (answers the "two machines" question)
- Each machine publishes its own status row keyed by `(user_id, device_id)` — `upsertStatus`, [relay.js:383](server/src/lib/server/relay.js), `ON CONFLICT(user_id, device_id)`.
- `getFeed` pulls **all** of a user's device rows and `mergeUserStatuses` combines them — [relay.js:491-540](server/src/lib/server/relay.js):
  - **Presence** = strongest mode across devices (max `MODE_RANK`). If either machine is broadcasting, the user shows broadcasting.
  - **Git stats** (commits/insertions/deletions/repos/uncommitted) **and** agent mix **are summed** across all broadcasting devices whose `client_day` equals the latest broadcasting device's day — `mergeGitStats` [relay.js:439-447], `mergeAgentMix` [relay.js:457-471]. **So yes: lines of code from both machines are combined** in the broadcast.
  - **Caveat:** only devices on the *same latest `client_day`* are summed. If the two machines disagree on "today" (timezone, clock skew, or one is a day stale), the off-day machine's lines are dropped. Quiet/offline devices contribute nothing.
  - `manual_status`, `derived_status`, and the non-summed cards (repo_aliases, spotify, weather, harness) come from a **single source device** (latest broadcasting), not merged.

This matters for the rework: keep per-device publishing + cross-device summing, and compute "online" recency from the **most recent activity across all devices**, not per device.

## Goals

- Remove "quiet" as a selectable presence mode (server `MODES` + client `PresenceMode` + copy).
- Remove "quiet" from the derived vibe vocabulary; no-activity becomes "offline / last seen …", not a vibe word.
- Replace the manual mode picker with **automatic presence**: online (green) if last activity within a threshold; otherwise "last seen vibing N minutes ago".
- Keep a **flexible, non-hardcoded** list of fun vibe labels — config/data-driven so labels can change without shipping a new app build. Exact set is intentionally TBD; only certain that "quiet" is out.
- Keep multi-device line summing working.
- Rewrite website + in-app copy to match product intent.

## Non-Goals / deferred

- The acknowledgment / "wave" notification and its UI indication — **explicitly not designed yet**, out of scope here.
- Finalizing the vibe-label set (left flexible/TBD).
- Whether an explicit "go invisible" opt-out survives (see open questions).

## Proposed model (draft)

- **Presence is derived, not chosen:**
  - online/green: most recent activity across the user's devices is within `THRESHOLD` (≈2 min, configurable).
  - otherwise: "last seen vibing {N} minutes ago" (rolling up to hours/days), from the last-activity timestamp.
- **Activity source:** simplest is the latest status row's `updated_at`; may want a dedicated `last_active` heartbeat (see open questions — current publish cadence is ~3 min, which is coarser than a 2-min window).
- **Vibe label** stays a derived word from daily stats, but the mapping lives in a flexible place (a small server-driven config the app fetches, or a committed shared JSON), not a hardcoded Swift switch. "quiet" removed.
- **Opt-out:** if we keep a "go invisible" option, it's a boolean "share presence" — not a 3-way mode. Open question.

## Affected code

**Server**
- [relay.js:7-8](server/src/lib/server/relay.js) — drop "quiet" from `MODES`/`MODE_RANK`; rethink as online/offline (or share/no-share).
- [relay.js:491-540](server/src/lib/server/relay.js) `mergeUserStatuses` + `derived_status` — recency-based presence; compute last-active across devices.
- [admin.js:25-26,290-298](server/src/lib/server/admin.js) + [admin/+page.svelte:60](server/src/routes/admin/+page.svelte) — update presence tally to new states.

**Client**
- [Models.swift:3-15](client/Vibes/Models.swift) `PresenceMode` — remove `.quiet`; likely collapse to derived presence + optional opt-out.
- `MainPanel` mode picker + [ContentView.swift:263](client/Vibes/ContentView.swift) detail text — replace with last-seen / online rendering.
- [GitScanner.swift:345-353](client/Vibes/GitScanner.swift) `deriveVibe` — remove "quiet"; move label list to flexible config.

**Copy**
- [+page.svelte:12-13,26,47](server/src/routes/+page.svelte) — remove "A quiet presence layer", "when they prefer quiet", "Broadcasting, Quiet, or Offline"; rewrite per intent below.

## Website + in-app copy (folds in the earlier note)

**Product intent:** Vibes is a fun, lightweight way to see which of your friends are coding at the same time as you, plus a for-fun glance at how many lines they've pushed recently — ambient presence, not a productivity tool.

**Audience (real people, accomplished/hobbyist engineers coding at odd hours):**
- Justin — retired engineer from Google and Facebook.
- Marcus's dad — retired engineer.
- A good buddy who works elsewhere but codes a lot in his spare time.
- They write code at all hours, often late at night. The joy is seeing someone else is online too.

**Tone:** mostly for fun, with the *slightest* bit of friendly competition (lines pushed). Possible future feature: a subtle way to acknowledge a friend's presence (a "wave").

**Design north star:** Teenage Engineering — clean, minimal, tactile, but playful. Their design metaphor/philosophy is the target.

**Homepage:** currently leans generic ("A quiet presence layer for coding friends"). Rewrite headline/subhead/steps toward the intent above; drop the mode-selection step. Keep it minimal. This supersedes the get-started copy touched in [[app-first-onboarding]] (which only updated the install steps).

## Open questions

- **Online threshold** — 2 min? configurable per relay?
- **Recency source & heartbeat** — latest `updated_at` vs a dedicated `last_active`. Publishing is ~3 min today; a 2-min online window needs a tighter heartbeat or it will flicker.
- **Keep an explicit "go invisible" opt-out**, or fully automatic presence?
- **Where the flexible vibe-label list lives** — server config endpoint the app fetches vs a committed shared JSON.
- **Multi-device "today" mismatch** — fix the `client_day` summing caveat as part of this, or leave it?
