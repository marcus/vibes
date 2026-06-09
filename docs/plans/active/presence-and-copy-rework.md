# Vibes: Presence Model & Copy Rework

Status: planning (not started). Captures intent and findings; refine before building.

## Purpose

Four related product changes:

1. **Rework presence.** Remove the "quiet" status entirely, move to an automatic recency-based signal ("online/green" if active recently, otherwise "last seen vibing N minutes ago"), and keep the fun status labels as a *flexible* list rather than hardcoded.
2. **Rewrite the website (and in-app) copy** to match what Vibes is actually for.
3. **Make multi-machine setup obvious on first launch.** The loading / first-run surface should ask whether the user already has Vibes installed somewhere else and explain how to connect both Macs to the same account.
4. **Remove coding-agent attribution.** Vibes should not know or display which coding agent, editor, assistant, or workflow produced code. The product should keep local Git stats and leave optional Spotify/weather cards as future extensions.

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
  - `manual_status`, `derived_status`, and the non-summed cards (repo_aliases, spotify, weather) come from a **single source device** (latest broadcasting), not merged.

This matters for the rework: keep per-device publishing + cross-device summing, and compute "online" recency from the **most recent activity across all devices**, not per device.

### Agent attribution (removed in current slice)
- Client config has repo-level agent labels via `AgentLabel`, `RepoConfig.agent`, and `SharingCards.agentMix` — [Models.swift:19-28,86-101,107-125](client/Vibes/Models.swift).
- The repo settings UI lets the user choose an agent per repo and toggle "share agent mix" — [ContentView.swift:357-359,396-404](client/Vibes/ContentView.swift).
- `GitScanner` counts commits by repo agent and emits an `agent_mix` status card — [GitScanner.swift:22,318-331](client/Vibes/GitScanner.swift).
- Server feed merge recomputes a cross-device `agent_mix` card — [relay.js:457-484,519-521](server/src/lib/server/relay.js).
- Tests and fixtures assert `agent_mix` behavior — [relay.test.js:342-352](server/tests/relay.test.js).

The bullets above describe the pre-removal behavior that was removed alongside the spec-v2 promotion. The new product decision is stronger than "hide it by default": the feature surface is gone and the client no longer publishes agent data. The only code-activity signal Vibes should share by default is aggregate Git stats. Repo aliases can remain optional; Spotify and weather can stay as dormant / future optional cards.

## Goals

- Remove "quiet" as a selectable presence mode (server `MODES` + client `PresenceMode` + copy).
- Remove "quiet" from the derived vibe vocabulary; no-activity becomes "offline / last seen …", not a vibe word.
- Replace the manual mode picker with **automatic presence**: online (green) if last activity within a threshold; otherwise "last seen vibing N minutes ago".
- Keep a **flexible, non-hardcoded** list of fun vibe labels — config/data-driven so labels can change without shipping a new app build. Exact set is intentionally TBD; only certain that "quiet" is out.
- Keep multi-device line summing working.
- On the loading / first-run screen, add a compact affordance: "Already using Vibes on another Mac?" Opening it explains that the same account token must be used on both machines, each machine publishes as its own device, and aggregate Git stats are combined in friends' feeds.
- Remove agent labels, agent settings, agent config, `agent_mix` payloads, and agent feed rendering. Do not replace this with another source-of-code attribution model.
- Rewrite website + in-app copy to match product intent.

## Non-Goals / deferred

- The acknowledgment / "wave" notification and its UI indication — **explicitly not designed yet**, out of scope here.
- Finalizing the vibe-label set (left flexible/TBD).
- Whether an explicit "go invisible" opt-out survives (see open questions).
- Implementing Spotify or weather cards. They may remain in config / schema if already harmless, but this plan does not build them.
- Any automatic detection of coding tools, editors, processes, agents, prompts, transcripts, or commit-message hints.

## Proposed model (draft)

- **Presence is derived, not chosen:**
  - online/green: most recent activity across the user's devices is within `THRESHOLD` (≈2 min, configurable).
  - otherwise: "last seen vibing {N} minutes ago" (rolling up to hours/days), from the last-activity timestamp.
- **Activity source:** simplest is the latest status row's `updated_at`; may want a dedicated `last_active` heartbeat (see open questions — current publish cadence is ~3 min, which is coarser than a 2-min window).
- **Vibe label** stays a derived word from daily stats, but the mapping lives in a flexible place (a small server-driven config the app fetches, or a committed shared JSON), not a hardcoded Swift switch. "quiet" removed.
- **Opt-out:** if we keep a "go invisible" option, it's a boolean "share presence" — not a 3-way mode. Open question.
- **Multi-machine guidance:** first-run loading/onboarding should include a small disclosure or secondary action, not a full setup fork. Copy should say, in plain terms:
  - If this is your first Mac, continue normally.
  - If Vibes is already set up on another Mac, use the existing-account / token path so both installs belong to the same person.
  - Each Mac can scan different repos; friends see one combined view for today's Git stats when both Macs are active.
- **Shared data model:** keep `git_stats` as the core activity card. Keep `repo_aliases` as optional. Leave `spotify` and `weather` as optional future card types if they are already part of config/contracts. Remove `agent_mix` entirely from client output and server merge output.

## Affected code

**Server**
- [relay.js:7-8](server/src/lib/server/relay.js) — drop "quiet" from `MODES`/`MODE_RANK`; rethink as online/offline (or share/no-share).
- [relay.js:491-540](server/src/lib/server/relay.js) `mergeUserStatuses` + `derived_status` — recency-based presence; compute last-active across devices.
- [relay.js:457-484,519-521](server/src/lib/server/relay.js) — remove `mergeAgentMix` and stop adding an `agent_mix` card.
- [admin.js:25-26,290-298](server/src/lib/server/admin.js) + [admin/+page.svelte:60](server/src/routes/admin/+page.svelte) — update presence tally to new states.
- [relay.test.js:342-352](server/tests/relay.test.js) + fixtures — remove agent-mix expectations and add a regression that unknown/legacy `agent_mix` cards are not re-emitted by feed merge if desired.

**Client**
- [Models.swift:3-15](client/Vibes/Models.swift) `PresenceMode` — remove `.quiet`; likely collapse to derived presence + optional opt-out.
- [Models.swift:19-28,86-101,107-125](client/Vibes/Models.swift) — remove `AgentLabel`, `RepoConfig.agent`, and `SharingCards.agentMix`; keep config decoding tolerant of older files that still contain these keys.
- `MainPanel` mode picker + [ContentView.swift:263](client/Vibes/ContentView.swift) detail text — replace with last-seen / online rendering.
- [ContentView.swift:357-359,396-404](client/Vibes/ContentView.swift) — remove "share agent mix" and per-repo agent picker UI.
- [GitScanner.swift:345-353](client/Vibes/GitScanner.swift) `deriveVibe` — remove "quiet"; move label list to flexible config.
- [GitScanner.swift:22,318-331](client/Vibes/GitScanner.swift) — stop counting per-agent commits and stop building `agent_mix`.
- First-run/loading view in `ContentView` / onboarding flow — add the "Already using Vibes on another Mac?" disclosure and route it to the existing-token / advanced path.

**Copy**
- [+page.svelte:12-13,26,47](server/src/routes/+page.svelte) — remove "A quiet presence layer", "when they prefer quiet", "Broadcasting, Quiet, or Offline"; rewrite per intent below.
- First-run client copy — explain multiple Macs without making multi-device feel like an advanced feature:
  - "Already using Vibes on another Mac?"
  - "Use the same account token on both Macs. Each Mac publishes its own device status, and Vibes combines today's Git stats for your friends."
  - "New to Vibes? Keep going and create your account here."

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

## Suggested implementation order

1. **Done: Plan/spec cleanup:** `spec-v2.md` no longer lists Agent Detection, `agent_mix`, or per-repo agent settings as current behavior. Privacy language is explicit: no raw agent/tool transcripts and no coding-tool attribution.
2. **Done: Client agent removal:** the repo agent picker and `agentMix` sharing toggle are gone. Config decoding remains backward-compatible because stale `agent` / `agent_mix` keys are ignored.
3. **Done: Scanner/payload cleanup:** `DailyGitStats.agentCommitCounts` and the `agent_mix` card builder are gone. Published payloads include `git_stats`, optional `repo_aliases`, and dormant Spotify/weather cards only.
4. **Done: Server merge cleanup:** `mergeAgentMix` is gone, tests/fixtures are updated, and legacy `agent_mix` device cards are not synthesized into feed output.
5. **First-run multi-machine copy:** add the loading/onboarding disclosure after the app-first onboarding plan lands or alongside that slice if the first-run surface is already being touched.
6. **Presence rework:** remove quiet and replace the manual mode picker with automatic recency once the smaller payload cleanup is stable.

## Repo Sharing Defaults

Adding a repo should mean "share its aggregate Git stats and its friendly alias." Keep the underlying config fields for now so older configs and future advanced controls still have somewhere to land, but remove the default UI and public-site emphasis around opting out of these two basics.

Implementation notes:

- New repos should default `share_alias` to `true`.
- The app should stop showing the "share Git stats" toggle in the main repo UI.
- The app should stop showing the per-repo "share alias" toggle in the main repo UI.
- Public website copy should not advertise repo-alias or Git-stats opt-outs as part of the core flow. Privacy copy can still say Vibes avoids raw repo paths, branch names, commit messages, and filenames.
- Keep Git stats and repo aliases as privacy-aware aggregate payloads; do not reintroduce code-origin, agent, editor, harness, or process attribution.

## Open questions

- **Online threshold** — 2 min? configurable per relay?
- **Recency source & heartbeat** — latest `updated_at` vs a dedicated `last_active`. Publishing is ~3 min today; a 2-min online window needs a tighter heartbeat or it will flicker.
- **Keep an explicit "go invisible" opt-out**, or fully automatic presence?
- **Where the flexible vibe-label list lives** — server config endpoint the app fetches vs a committed shared JSON.
- **Multi-device "today" mismatch** — fix the `client_day` summing caveat as part of this, or leave it?
- **Existing-account path wording** — should first-run link directly to an "I already have a token" screen, or show instructions first and keep the token entry in Advanced?
- **Legacy agent payload handling** — should the server merely stop re-emitting merged `agent_mix`, or also strip legacy per-device `agent_mix` cards when choosing singleton cards from older clients? Recommendation: strip them in feed output so friends never see stale agent attribution.
