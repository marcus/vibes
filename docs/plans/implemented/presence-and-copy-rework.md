# Vibes: Presence Simplification & Copy Rework (Online / Offline)

Status: planning (not started). Captures intent, the full touchpoint map, and concrete changes.

## Purpose

Collapse Vibes' presence model to **two states — online and offline — and nothing else**, and rewrite the copy to match. Specifically:

1. **Remove the "quiet" presence mode** entirely.
2. **Remove the word "broadcasting"** everywhere it appears (UI, copy, internal mode names, docs). The sharing-on state is just **online**.
3. **Remove the derived "vibe" labels** entirely (ship mode, wandering, yak shaving, vibing, warming up, quiet). There is no fun status word anymore.
4. Make presence **mostly automatic** with **one manual override**: you are online when you've been active recently and haven't hidden yourself; you can flip yourself **offline** (invisible/paused) at will.
5. **Rewrite website + in-app copy** to describe online/offline ambient presence with a for-fun glance at lines pushed.

### Explicitly deferred to a later phase (do not touch here)

- **Repo sharing defaults** (share-alias / share-git-stats toggles and their UI). Leave the existing config fields and toggles exactly as they are.
- **Multi-device aggregation** (cross-device line summing, cross-device "last active"). This phase derives presence from the existing single merge source; it does not change `mergeGitStats`, the `client_day` summing, or per-device fan-in.
- The **acknowledgment / "wave"** interaction — not designed yet.
- **Agent / code-origin attribution** — already removed in a prior slice; out of scope and not to be reintroduced.
- **The in-app UI rework** (TE-inspired presence control, merged feed+friends **cards**, settings screen, settings-as-LLM-prompt) — owned by [[app-ui-rework]]. This plan only changes the presence *data model*; it does not restyle the app shell.

## Target model

**Two states, derived by default, with one manual override.**

- **Online** — the user is sharing *and* has published activity within the **10-minute** recency threshold. Friends see a green/"online" indicator plus the optional for-fun cards (aggregate Git stats, optional manual note, optional repo alias).
- **Offline** — either the user has flipped themselves offline (invisible/paused), *or* they are sharing but haven't published within 10 minutes (laptop asleep, app closed, idle). Friends see **friendly last-seen language** built from the timestamp, e.g. **"online 10 hours ago"** / "online 5 minutes ago" (rolling minutes → hours → days). When there's no timestamp at all, just "offline". No cards.

**The only manual control** is an Online ⇄ Offline toggle (default Online). Flipping to Offline hides you immediately regardless of activity. There is no third mode, no "broadcasting" label, and no vibe word anywhere.

**Words the user ever sees:** `online`, `offline`, and `online … ago`. That's it.

### What stays (untouched by this phase)

- The **aggregate Git-stats card** (commits / insertions / deletions / repos / uncommitted) — this is the "for-fun glance at lines pushed" and is the whole point. Keep it.
- The **optional free-text manual status note** (`manual_status`) — user-authored, not a derived label, so it survives. (Minor open question below on whether to keep it.)
- **Optional repo aliases** card and all repo-sharing config fields/toggles — deferred phase owns these.
- Dormant Spotify / weather card types in config/contract — leave as-is.

## Why

- **"Quiet" was a do-not-disturb mode, but Vibes has nothing to disturb you with.** There is no message, no ping, no interruption. A "online but don't disturb" state is meaningless, so it collapses into "offline."
- **"Broadcasting" sounds posed/performative.** You're either online and coding or you're not — "online" carries that without the staged feeling.
- **The derived vibe labels are guesswork dressed as status.** They inferred a mood from line counts ("ship mode", "yak shaving"). They add a hardcoded vocabulary to maintain, imply judgment about how someone's day is going, and aren't what the product is for. The honest signal is: are they around, and roughly how much have they shipped. The Git-stats card already says the second part; presence says the first.

## Current behavior (touchpoint map)

Every place the three concepts (quiet mode, "broadcasting" wording, derived vibe) live today:

### Presence mode — 3-way `broadcasting / quiet / offline`

- **Client enum** `PresenceMode { broadcasting, quiet, offline }` + `.label` strings — [Models.swift:3-17](client/Vibes/Models.swift).
- **Persisted config** `PresenceConfig.mode`, default `.broadcasting` — [Models.swift:121-131](client/Vibes/Models.swift).
- **App state + publish** `AppModel.mode` default `.broadcasting`, `setMode`, restore from config — [AppModel.swift:10,48,158,255-259](client/Vibes/AppModel.swift).
- **Main-panel mode picker** (menu, all cases) — [ContentView.swift:131-141](client/Vibes/ContentView.swift).
- **Menu-bar mode picker** (duplicate, all cases) — [VibesApp.swift:60-67](client/Vibes/VibesApp.swift).
- **Friend-row detail text** `"online, not broadcasting"` (quiet) vs `"offline"` — [ContentView.swift:262-266](client/Vibes/ContentView.swift).
- **Detail popover** shows `status.mode.label` — [ContentView.swift:305](client/Vibes/ContentView.swift).
- **Payload build** gates cards/manual/derived on `mode == .broadcasting`; sets `derivedStatus` to vibe when broadcasting else `mode.rawValue` — [GitScanner.swift:280-291](client/Vibes/GitScanner.swift).
- **Server modes** `MODES = {broadcasting, quiet, offline}`, `MODE_RANK {offline:0, quiet:1, broadcasting:2}` — [relay.js:7-8](server/src/lib/server/relay.js).
- **Server publish** validates mode; only `broadcasting` shares cards/manual/derived; offline/quiet replace blob — [relay.js:338,353-371](server/src/lib/server/relay.js).
- **Server feed merge** strongest mode across devices via `MODE_RANK`; presence/derived derived from mode — [relay.js:460-540](server/src/lib/server/relay.js).
- **Merged client model** `MergedStatus.mode` + detail rendering — [Models.swift:273-296](client/Vibes/Models.swift).
- **Admin** `PRESENCE_CASE` / `RANK_TO_MODE` / per-user presence, tally `{broadcasting, quiet, offline}` — [admin.js:23-26,87,105,190-206,290-307](server/src/lib/server/admin.js).
- **Admin UI** presence stat with `quiet` / `offline` sub-rows, "Broadcasting now" list — [admin/+page.svelte:55-83](server/src/routes/admin/+page.svelte).
- **Admin badge** `StateBadge` tones for `broadcasting / quiet / offline` (+ `--admin-quiet` CSS var) — [StateBadge.svelte:6-8,58](server/src/lib/components/admin/StateBadge.svelte).

### Derived "vibe" label

- `deriveVibe(stats)` → `"ship mode" | "wandering" | "yak shaving" | "vibing" | "warming up" | "quiet"` — [GitScanner.swift:328-335](client/Vibes/GitScanner.swift).
- `derived_status` carried in payload, defaulted to `"vibing"` server-side, surfaced in feed — [relay.js:366-368,463,497](server/src/lib/server/relay.js).
- `MergedStatus.derivedStatus` + the friend-row **dot tint** switch (`ship mode`=red, `vibing`=green, `yak shaving`=orange…) — [Models.swift:283-288](client/Vibes/Models.swift), [ContentView.swift:283-290](client/Vibes/ContentView.swift).
- `derived_status` field in `StatusPayload` coding keys — [GitScanner.swift:133](client/Vibes/GitScanner.swift).

### Copy

- Homepage `<title>`/meta description, h1 "A quiet presence layer for coding friends.", subhead "…and when they prefer quiet.", image alt "quiet friend presence feed", step 4 "choose Broadcasting, Quiet, or Offline." — [+page.svelte:1-49](server/src/routes/+page.svelte).
- AGENTS.md line 14 "The user chooses Broadcasting, Quiet, or Offline." (Note: line 64 "spare, premium, and quiet" is an *aesthetic* adjective — leave it.) — [AGENTS.md](AGENTS.md).
- Client runbook "Presence Modes & Vibes … Broadcasting, Quiet, and Offline … Derived vibes …" — [client-runbook.md:32](docs/client-runbook.md).
- spec-v2.md many references (modes, Quiet section, derived vibe list) — [spec-v2.md:30,51,69-79,116,127,249,261,615,659,679,846,979,992](docs/plans/active/spec-v2.md).

### Contract fixtures & tests

- `shared/contract/status-broadcasting.json` and `feed-response.json` carry `"mode": "broadcasting"`, `"derived_status": "vibing"`.
- `server/tests/relay.test.js` has quiet-specific cases (`mode/derived_status: "quiet"`) at lines 299-312, 377-379, 427.
- `server/tests/admin.test.js:51` uses `derived_status: "vibing"`.

## Changes by area

### Client (SwiftUI)

1. **Collapse the enum.** `PresenceMode` → two cases: `online`, `offline` (rename `broadcasting`→`online`, delete `quiet`). Labels `"Online"` / `"Offline"`. — [Models.swift:3-17](client/Vibes/Models.swift)
2. **Config + state defaults** flip `.broadcasting` → `.online`. No tolerant decoding — just change the default and the cases. (Pre-public, two installs; the config on both machines gets rewritten on next launch. See [[no-legacy-until-public]].) — [Models.swift:121-131](client/Vibes/Models.swift), [AppModel.swift:10,48,158](client/Vibes/AppModel.swift)
3. **Reduce both mode pickers to two states.** The main panel (`ContentView`) and menu bar (`VibesApp`) currently render a 3-item `Picker` over `allCases`; with the enum collapsed they become Online/Offline. `setMode` stays as the action. **The actual in-app presentation (the TE-inspired Online/Offline control) is owned by [[app-ui-rework]]** — this plan only needs the two-state enum to flow through. — [ContentView.swift:131-141](client/Vibes/ContentView.swift), [VibesApp.swift:60-67](client/Vibes/VibesApp.swift)
4. **Delete `deriveVibe` and `derived_status`.** Remove the function, the `StatusPayload.derivedStatus` field and its coding key, and stop sending the field. — [GitScanner.swift:280-291,328-335,133](client/Vibes/GitScanner.swift)
5. **Friend-row data model.** Remove `derivedStatus` from `MergedStatus` and the vibe-based `tint` switch. The presence signal is just **online / offline** plus, when offline-but-recent, the `last_seen` timestamp for **"online {relative} ago"** language (SwiftUI's `.formatted(.relative(...))` gives the phrasing). **The friend-row/card rendering itself is owned by [[app-ui-rework]]** (which reconceives the row as a friend card); this plan only removes the vibe data and ensures `mode` + `last_seen` are available. — [Models.swift:273-296](client/Vibes/Models.swift), [ContentView.swift:262-266,283-296,305](client/Vibes/ContentView.swift)

### Server (relay)

6. **Modes → two values.** `MODES = {online, offline}`; `MODE_RANK {offline:0, online:1}`. Reject anything else — no legacy `broadcasting`/`quiet` acceptance (both installs update together; see [[no-legacy-until-public]]). — [relay.js:7-8,338](server/src/lib/server/relay.js)
7. **Sharing gate** keyed on `online` instead of `broadcasting`: cards/manual shared only when `online`; `offline` replaces the blob with no cards (same shape quiet/offline had). — [relay.js:353-371](server/src/lib/server/relay.js)
8. **Remove `derived_status`.** Stop reading/defaulting/emitting it in publish and in `mergeUserStatuses`. — [relay.js:366-368,463,497](server/src/lib/server/relay.js)
9. **Recency-based liveness in the feed.** In `mergeUserStatuses`, compute the friend's effective state: if mode is `online` *and* the source row's `updated_at` is within **10 min**, report `online`; if `online` but stale, report `offline` and surface the `updated_at` as `last_seen` so the client can render "online {relative} ago"; if mode `offline`, report `offline` with no `last_seen`. Keep using the **existing single merge source / `client_day` logic untouched** — no multi-device changes. — [relay.js:460-540](server/src/lib/server/relay.js)
10. **Contract.** Rename `shared/contract/status-broadcasting.json` → `status-online.json` with `"mode": "online"` and no `derived_status`; update `feed-response.json` likewise (add `last_seen` where modeled). No `schema_version` bump needed. — [shared/contract/](shared/contract/)

### Admin

11. **Tally → `{online, offline}`**; update `PRESENCE_CASE`, `RANK_TO_MODE`, the per-user presence reduce, and the "Broadcasting now" query/label (→ "Online now"). — [admin.js:23-26,87,105,190-206,290-322](server/src/lib/server/admin.js)
12. **Admin UI**: presence stat shows online/offline; rename "Broadcasting now" section; empty-state copy. — [admin/+page.svelte:55-83](server/src/routes/admin/+page.svelte)
13. **`StateBadge`**: replace `broadcasting`/`quiet` tones with `online` (live) / `offline` (faint); drop the `quiet` entry and `--admin-quiet` usage if now unused. — [StateBadge.svelte:6-8,58](server/src/lib/components/admin/StateBadge.svelte)

### Tests

14. **`relay.test.js`**: rename `broadcasting`→`online` everywhere; delete/replace the three quiet-specific cases (299-312, 377-379, 427) with offline equivalents; remove `derived_status` assertions; add a test for the **recency → offline + `last_seen`** transition (online row within 10 min reports online; same row aged past 10 min reports offline with `last_seen`). — [relay.test.js](server/tests/relay.test.js)
15. **`admin.test.js`**: drop `derived_status`; update presence-tally expectations. — [admin.test.js:51](server/tests/admin.test.js)

### Copy & docs

16. **Homepage** — rewrite (concrete strings below). — [+page.svelte](server/src/routes/+page.svelte)
17. **AGENTS.md:14** — replace "The user chooses Broadcasting, Quiet, or Offline." with the online/offline model. Leave the aesthetic "quiet" on line 64.
18. **client-runbook.md:32** — replace the "Presence Modes & Vibes" line with "Presence: online / offline, derived from recent activity with a manual offline toggle."
19. **spec-v2.md** — update the modes/quiet/derived-vibe sections to the two-state model (larger edit; can trail the code but should not stay contradictory).

## Concrete homepage copy

`server/src/routes/+page.svelte` — replace the marked strings. Tone target stays Teenage-Engineering minimal.

| Element | Current | Proposed |
|---|---|---|
| `<title>` | `Vibes` | `Vibes` (keep) |
| meta description | "Private ambient presence for small coding groups." | "See which friends are online and coding — private ambient presence for small groups." |
| h1 | "A quiet presence layer for coding friends." | **"See who's coding right now."** |
| subhead | "See who is around, what kind of day they are having, and when they prefer quiet." | **"Vibes shows which friends are online and how much they've shipped today. Ambient presence for people who code at odd hours."** |
| description | "Vibes is a Mac app for small groups. It turns local Git activity and an optional status into a simple friend feed." | "A Mac app for small groups. It turns your local Git activity into a simple, private friend feed — no chat, no noise." |
| privacy | (unchanged) | keep as-is |
| image alt | "…showing a quiet friend presence feed." | "…showing a feed of which friends are online and coding." |
| step 4 | "Add your local repos and choose Broadcasting, Quiet, or Offline." | **"Add your local repos. You're online while you're coding, and one tap takes you offline."** |

(These are starting strings, not final — the only hard constraints are: no "quiet", no "broadcasting", no vibe-label words, online/offline only.)

## No legacy support

Pre-public, exactly two installs (this Mac + MacBook Pro), no external users. Rip and replace — **no** legacy-value normalization, **no** tolerant config decoding, **no** migration scripts, **no** schema-version bump. Both machines update together and rewrite their own config/status on next launch. (See [[no-legacy-until-public]].) Reinstate normal back-compat discipline once Vibes goes public.

## Suggested implementation order

1. **Server two-state modes + drop `derived_status` + recency liveness** (steps 6-10).
2. **Client enum/config/pickers/rendering** (steps 1-5).
3. **Admin** (steps 11-13).
4. **Tests + contract** (steps 14-15, 10).
5. **Copy & docs** (steps 16-19).

## Settled decisions

- **Online threshold: 10 minutes.** Within 10 min of last publish → online; older → offline with a last-seen timestamp.
- **Last-seen wording: friendly relative**, e.g. "online 10 hours ago". Use the merge row's `updated_at` (single-source) — fine here since multi-device "last active" is the deferred phase.
- **Keep `manual_status`** — user-authored note, not a derived label.
- **No `schema_version` bump.**

## Open questions

- **Offline-toggle wording in-app** — moved to [[app-ui-rework]], which owns the TE-inspired presence control. (Direction there: a labeled Online / Offline state, not a "Go offline" checkbox.)
