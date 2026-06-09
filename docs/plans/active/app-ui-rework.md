# Vibes: In-App UI Rework — TE-inspired controls, unified friend cards, settings-as-prompt

Status: planning (not started). Captures intent and direction; concrete component/API work to be detailed during implementation.

## Purpose

Rework the Vibes Mac app's primary surface from a three-tab utility panel into a single, opinionated home built around **friend cards**, with a **Teenage-Engineering-inspired online/offline control**, and a **settings model where the user never hand-edits `config.json`**.

This plan owns the **in-app UI**. It builds on top of the data/model changes in [[presence-and-copy-rework]] — that plan collapses presence to two states (`online` / `offline`) and provides the `last_seen` timestamp; this plan owns how the toggle and the friend rows actually look and behave. The two in-app rendering steps and the in-app toggle-wording open question have been moved here from that plan.

## Relationship to the presence plan

- **Depends on** the two-state model from [[presence-and-copy-rework]] landing first (or in tandem): `PresenceMode ∈ {online, offline}`, no derived vibe, `last_seen` available on stale-online friends.
- That plan guarantees the **data**; this plan owns the **rendering**. Specifically, the following moved here:
  - Replacing both mode pickers (main panel + menu bar) with a single Online/Offline control — now the TE-inspired button below.
  - Friend-row rendering — now reconceived as the **friend card** below.
  - The open question "Offline-toggle wording in-app."

## Design direction

**Reference: Teenage Engineering's instruments, not their website.** Think OP-1 / PO / TX-6 hardware — the physical control language, not the marketing site.

- **Not full skeuomorphism.** We are not rendering screws, brushed metal, or photoreal knobs. We borrow the *vocabulary*: confident flat color fields, chunky tactile controls, clear state, a little playfulness.
- **Borrow:** their color palette (saturated accent pops against neutral/dark chassis), their shapes (rounded rectangles, pill buttons, segmented blocks, dot indicators), their typographic restraint, and the sense that each control is a real physical object you press.
- This is distinct from the current spare/minimal styling — it's warmer and more tactile, but still restrained.
- The existing `stereo-design-system` skill is the *wrong* direction (that's hi-fi/brass/skeuo); the `linear-design-patterns` skill is closer on density/keyboard but wrong on warmth. Treat TE instruments as the primary visual reference and pull tokens from there.

> Open: capture a concrete palette + shape token set (a small `DESIGN.md` for the app) before building the cards, so the card and the toggle share one language.

## Information architecture: kill the three tabs

Today `MainPanel` has three sections — `feed`, `repos`, `friends` — switched by a segmented button row ([ContentView.swift:118-166](client/Vibes/ContentView.swift)). Replace that with:

1. **Home (cards)** — the merge of today's **feed** and **friends** *viewing*. One card per friend (plus a "you" card). This is the app's main surface.
2. **Settings** — a new screen that owns **repos** (moved out of its own tab) and the settings-as-prompt flow below.

The **three-tab switcher goes away.** Home is the default and primary view; Settings is reached from the gear button (which changes behavior — see below).

### Open: where does the friend *invite/add* flow live?

The current `friends` tab is two things mashed together: (a) *viewing* friends' presence (→ now the cards) and (b) *adding* friends (create invite link, accept code, pending invites — [ContentView.swift:397-493](client/Vibes/ContentView.swift)). The cards absorb (a). The add-friend flow (b) needs a new home — likely inside **Settings**, or behind a "+" affordance on Home. Decide during implementation. Default recommendation: put add-friend in Settings next to repos.

## The presence control — TE-inspired Online/Offline button

Replaces the two `Picker(.segmented)` over `PresenceMode.allCases`:
- Main panel — [ContentView.swift:131-141](client/Vibes/ContentView.swift)
- Menu bar — [VibesApp.swift:60-67](client/Vibes/VibesApp.swift)

- A single, **tactile two-state control** (Online ⇄ Offline), styled as a TE-instrument button/switch — a real "press it" object, not a stock segmented control. Online is the default and the "lit" state (saturated accent); Offline reads as dimmed/at-rest.
- `model.setMode(_:)` stays as the action; only the presentation changes.
- The menu-bar version can be a more compact variant of the same control, but should feel like the same object.
- **Resolves the moved open question:** the control reads as a labeled **Online / Offline** state (not a "Go offline" checkbox). Final affordance (toggle vs. illuminated push-button) chosen during implementation against the TE reference.

## Friend cards — the core component

This is the **single most important component in the app** and the thing we'll iterate on most, so build it as a clean, well-isolated, reusable view (its own file, previewable, parameterized — not buried inline in `ContentView`).

**One card per friend** (and a "you" card), replacing the current `StatusRow` list ([ContentView.swift:235-295](client/Vibes/ContentView.swift)).

Each card shows:
- **Online/offline status** — the dot/state, using the two-state model. When offline-but-recently-online, the "online {relative} ago" last-seen language (data from [[presence-and-copy-rework]]).
- **Commits per day** — surfaced prominently (today's commit count; the existing `git_stats` card summary has commits/insertions/deletions/repos).
- **Repos they worked on** — the repo names/aliases the friend touched today.
- (Keep room for the optional manual status note, which survives in the presence plan.)

**Layout & overflow:**
- Cards laid out so several fit on screen at once.
- **Vertical scrolling** when there are more friends than fit.
- **Or adaptive shrink** — cards can compact to fit more without scrolling. Decide the threshold/behavior during implementation (e.g. a comfortable size by default, a denser size past N friends). Either way, the card component should be designed to render well at more than one size.

**Quality bar:** these cards are the product's face and our main editing surface — invest in them. Treat the card as a first-class component with explicit states (online / offline-recent / offline-hidden / you / empty), good empty/loading handling, and SwiftUI previews for each state.

## Settings screen + settings-as-prompt

Two changes here.

### 1. New Settings screen owns repos

Move the repos UI (add/remove/alias/share-alias, the `share Git stats` toggle) out of the old `repos` tab into a dedicated **Settings** screen — [ReposSection / RepoRow, ContentView.swift:322-395](client/Vibes/ContentView.swift). Likely also the add-friend flow (see open question above).

### 2. The gear button → "edit settings via LLM" pop-out

Today the footer gear calls `openConfigFolder()`, which reveals `config.json` in Finder for hand-editing — [Footer, ContentView.swift:537-564](client/Vibes/ContentView.swift), [AppModel.openConfigFolder, AppModel.swift:345-347](client/Vibes/AppModel.swift). **The user should never hand-edit `config.json`.**

Replace with a **clean pop-out** that hands the user a **copy-paste prompt to give to an LLM** to update their settings:
- Click the gear → a tidy popover/sheet opens.
- It presents a **copy-to-clipboard prompt** containing: the current `config.json` (or the relevant slice), a description of the schema/allowed fields, and instructions telling the LLM to return an updated config.
- The user pastes that into their LLM of choice, edits via conversation, and brings the result back.

**Open: how does the edited config get back in?** Options to decide during implementation:
- Paste the LLM's returned JSON into a text box in the pop-out → validate → write to `config.json`.
- Or the LLM writes the file directly (it has filesystem access) and the app just hot-reloads.
- Recommendation: support paste-back-and-validate in the pop-out so it works regardless of whether the LLM can touch the filesystem. Validate against the config schema and surface errors before persisting.

This pairs naturally with the structured-settings screen (repos, sharing toggles) for the common edits, with the LLM-prompt escape hatch for everything else.

## Files / touchpoints (initial)

- [ContentView.swift](client/Vibes/ContentView.swift) — remove `Section` tabs + switcher; new `Home` (cards) view; extract `FriendCard` to its own file; move repos into Settings; rework `Footer` gear; add Settings screen + LLM-prompt pop-out.
- [VibesApp.swift:60-67](client/Vibes/VibesApp.swift) — menu-bar presence control → TE-style.
- [AppModel.swift:345-347](client/Vibes/AppModel.swift) — replace/augment `openConfigFolder()` with the prompt-builder + (optional) paste-back-and-validate writer.
- New: a small app `DESIGN.md` capturing the TE-derived color/shape tokens shared by the toggle and the cards.
- `VibeColor` / styling — extend with the TE palette tokens.

## Open questions

1. **Add-friend flow home** — Settings vs. a "+" on Home (recommend Settings).
2. **Card sizing** — fixed comfortable size + scroll, vs. adaptive shrink past N friends (recommend: design the card to render at ≥2 sizes, start with comfortable+scroll).
3. **Presence control form** — toggle vs. illuminated push-button, against the TE reference.
4. **Settings paste-back** — text-box-validate-write vs. LLM-writes-file-and-reload (recommend support paste-back-and-validate).
5. **TE tokens** — lock a concrete palette/shape set in `DESIGN.md` before building cards.

## Suggested order

1. Lock the TE design tokens (`DESIGN.md`) — palette + shapes shared by toggle and cards.
2. Build the **FriendCard** component in isolation (all states + previews).
3. Replace the three-tab `MainPanel` with **Home (cards)** + the TE **presence control**.
4. Build the **Settings** screen (repos moved in, add-friend if chosen here).
5. Replace the gear's `openConfigFolder` with the **settings-as-prompt** pop-out (+ paste-back-and-validate).
6. Apply the TE control styling to the **menu-bar** presence control.
