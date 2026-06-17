# Vibes: Anonymous "distant" peers in the orbit

Status: proposed. Open product direction — see "Decision pending" below.

## Purpose

A user with one connection sees a nearly empty sky. Backfill the orbit with a
small number of anonymized peers so it reads as ambient population — present but
clearly secondary.

Two flavors, depending on how many real eligible users exist:

- **Pool ≥ 8:** show up to 4 anonymized peers carrying **only** real commit
  counts and LOC (insertions / deletions / churn). No identity of any kind.
- **Pool < 8:** show several **statless** orbs — faint shapes only, no numbers,
  no identity. Just "others are here." This avoids re-identification when the
  crowd is too small for numbers to be anonymous, while still filling the sky.

In all cases: peers appear **only in orbit view**, never in list view, and carry
no handle, display name, avatar, project / repo names, status text, music, or
weather. They render smaller, dimmer, and further back than real connections.

This is as much a privacy feature as a rendering feature. The hard part is not
drawing faint orbs — it is guaranteeing the numbers can't be re-identified.

## Decision pending (Marcus is sleeping on it)

Which direction to take for the early-network / tiny-pool case is **not yet
settled**. Candidates, not mutually exclusive:

1. **Statless orbs** (the < 8 fallback above) — faint shapes, no data.
2. **Aggregate sky stat** — a single ambient line, e.g. "47 developers shipped
   code today." Zero re-identification risk; works at any pool size. Cheapest
   and safest. Could be the thing we ship first, or the permanent < 8 behavior.
3. **Empty sky** — show nothing until there's a real crowd; lean harder on the
   invite nudge instead.
4. **Per-orb anonymized numbers** (the ≥ 8 behavior) — the richest, but only
   honest once the pool is large.

Note Marcus's framing: Vibes is social by nature, but it might also be genuinely
useful / fun for **just two people**. That argues against "empty sky" as the
two-person experience and toward *something* ambient even at very small scale —
which is what the statless-orbs fallback is for. Worth deciding whether the
two-person case is served by statless orbs, an aggregate line, or by leaning
entirely on real-connection richness + invites.

Current leaning (revisit in the morning): ship the **aggregate sky stat** first
(safe at any size, immediately useful), add **statless orbs** for the < 8 case,
and gate **per-orb anonymized numbers** behind the k ≥ 8 pool check + a server
flag until the active daily pool is clearly large enough.

## Architecture context (where things live)

Confirmed by reading the current code:

- Feed assembly: `getFeed(db, viewer, nowMs)` — `server/src/lib/server/relay.js:1037`.
  Returns `{ you, friends }`. Friends are accepted friendships only.
- Server-side card whitelist (existing redaction posture): `relay.js:1006` —
  only `git_stats`, `repo_aliases`, `music`, `weather` survive; unknown cards are
  dropped server-side. We extend this posture: ghosts get an even stricter
  serializer.
- Identity serializers: `publicUser()` (`relay.js:109`) and `feedUser()`
  (`relay.js:120`) both still carry identity — do **not** reuse them for ghosts.
- Feed endpoint: `server/src/routes/api/feed/+server.js`.
- Client feed model: `FeedResponse`, `MergedStatus`, `UserSummary`,
  `StatusCard` in `client/Vibes/Models.swift`. Derived churn / insertions /
  deletions accessors at `Models.swift:590` onward.
- Sender-side redaction defaults (strong opt-in privacy posture):
  `SharingRedactionsConfig` / `SharingCardsConfig` in `Models.swift:89`–`217`.
- Orbit rendering: `OrbitView` / `OrbView` in `client/Vibes/OrbitView.swift`.
  - View switch (orbit vs list): `client/Vibes/ContentView.swift:1013`–`1152`,
    `@AppStorage("feedViewMode")`.
  - Sky members + churn sort: `OrbitView.swift:76`.
  - Hand-tuned constellation slots: `OrbitView.swift:94`; staggered grid
    fallback for big skies: `OrbitView.swift:112`.
  - Orb diameter (sqrt-area churn scaling, min 44 / max 84):
    `OrbitView.swift:226`–`236`.
  - Float/bob driven by `TimelineView`: `OrbitView.swift:256`.
  - Muted-orb vocabulary already exists in the "drifting" dock `DrifterItem`
    (~0.3 saturation, ~0.8 opacity), `OrbitView.swift:441`–`515`.
  - Empty-sky copy: `OrbitView.swift:59`.

## Server: anonymized source in the feed

Add a third array to the feed response:

```js
return {
  you: merged[0],
  friends: merged.slice(1),
  ghosts: selectGhosts(db, viewer, nowMs), // [] when suppressed
};
```

`selectGhosts(db, viewer, nowMs)`:

1. **Candidate pool** — users who are not the viewer and **not an accepted
   friend of the viewer** (so a friend's numbers can never be stripped of their
   name and correlated back), who have visible `git_stats` for the current day,
   and who have opted in (see Settings).
2. **Today only** — same `client_day` semantics as friends so churn / typical
   comparisons stay coherent.
3. **k-anonymity gate** — let `n` = eligible pool size, `GHOST_MIN_POOL = 8`.
   - `n >= 8`: sample up to 4, emit **with** numbers (`ghostStatus`).
   - `0 < n < 8`: emit several (e.g. 3–4) **statless** placeholders — no per-user
     data at all, just a count of faint orbs to render. Could be as minimal as
     `{ kind: "anon", count: 3 }`, or N tokens with ephemeral ids and no metrics.
   - `n == 0`: `[]`.
4. **Random sample, not top-N** — top-by-churn is itself a fingerprint. Seed the
   RNG per-viewer-per-day so the set is stable within a session but rotates
   daily.
5. **Strict serializer** (numbers case) — a new function, **not**
   `feedUser` / `publicUser`:

```js
function ghostStatus(user, status, viewerId, day) {
  return {
    id: ephemeralId(user.id, viewerId, day), // HMAC, non-reversible, daily-rotating
    commit_count: status.commit_count,
    insertions: bucket(status.insertions),   // round to ~2 sig figs
    deletions:  bucket(status.deletions),
    churn:      bucket(status.churn),
    typical_churn: status.typical_churn ? bucket(status.typical_churn) : null,
  };
}
```

Everything else — the `user` object, all `cards`, `repo_aliases`, `music`,
`weather`, `manual_status`, `commit_streak`, `timezone`, `updated_at` — is
**dropped at the server and never serialized**. Mirrors the existing card
whitelist philosophy: the client never receives what it must not show.

`bucket()` rounds LOC to ~2 significant figures so exact values
(`+1,247 −389`) collapse into shared bins (`+1.2k −390`). Commit counts are
low-cardinality; leave as-is.

`ephemeralId()` = HMAC(server secret, `user_id | viewer_id | day`). Non-reversible
and not trackable across days.

## Client: model changes

Use a **distinct type**, not a flag on `MergedStatus`, so the compiler makes it
impossible for a ghost to render identity (the fields simply don't exist):

```swift
struct GhostPeer: Codable, Identifiable {
  let id: String
  let commitCount: Int?     // nil => statless orb (pool < 8)
  let insertions: Int?
  let deletions: Int?
  let churn: Int?
  let typicalChurn: Int?
}

struct FeedResponse: Codable {
  let you: MergedStatus
  let friends: [MergedStatus]
  let ghosts: [GhostPeer]?  // optional => backward compatible with old servers
}
```

## Client: render in orbit only

List view (`feedList`, `FriendCard.swift`) takes `friends` and is left untouched
— ghosts are never passed to it, satisfying "orbit only."

- **Background layer.** Render ghosts in a `ZStack` layer behind the real orbs
  (`OrbitView.swift:43`), in peripheral / edge slots so real connections keep
  the prominent center constellation slots. Ghosts get their own outer-ring
  positions; they don't compete for `skyMembers` slots.
- **Smaller ("distant").** New `GhostOrbView` with a tighter diameter range
  (e.g. min 28 / max 52 vs real 44 / 84), same sqrt-area churn scaling for the
  numbered case so a busy ghost still reads busier. Statless ghosts get a fixed
  small diameter.
- **Muted.** Whole-orb `.opacity(~0.4)`, desaturated neutral fill, softer/smaller
  glow. Borrow the `DrifterItem` muting vocabulary and push further back.
- **Generic visual — no identity leak.** No `AvatarFill` (that gradient is
  derived from identity). Use one neutral fill (faint slate) so all ghosts are
  visually interchangeable. Numbered ghosts keep a **simplified churn ring**
  (green/red split by adds-vs-deletes — the one encoding we legitimately have);
  **no** lap badge, repo moons, music chip, or name labels.
- **Numbers only, faint.** Numbered ghosts show one tiny caption,
  e.g. `+1.2k −340 · 8c`, tertiary color. Statless ghosts show nothing.
- **No interaction.** Not tappable / hoverable; excluded from a11y focus or
  labeled generically ("another developer, 8 commits today" / "another
  developer").
- **Float slightly slower.** Reuse `floatOffset` (`OrbitView.swift:256`) with a
  longer period so distant orbs drift more languidly — reinforces depth.
- **Empty-sky copy** (`OrbitView.swift:59`): when ghosts are present and the
  viewer has 0 real friends, soften to something like "You and a few others,
  building today" while keeping the invite nudge.

## Privacy & re-identification analysis

Showing real numbers from real people, even unlabeled, is a de-anonymization
surface. Mitigations:

- **Friends excluded from the pool** — can't strip a known friend's name and
  correlate.
- **k-anonymity gate (≥ 8)** — no numbered ghosts until the crowd is genuinely a
  crowd. Below that, statless orbs only. Important: at the app's current stage
  ("many users have 1 connection"), this likely means numbered ghosts stay dark
  for a while — which is the honest behavior, and exactly why the statless /
  aggregate fallbacks matter.
- **Bucketing / rounding** — defeats exact-LOC fingerprints.
- **Random sample, not top-N** — ordering by any visible metric leaks rank.
- **Ephemeral rotating ids** — non-reversible, not trackable across days.
- **No timing / streak / timezone** — strong correlators, all dropped.

## Settings (consent model — also pending)

The app's existing posture is strong opt-in privacy (`SharingRedactionsConfig`
defaults everything to redacted). Two models:

- **Opt-out (default-on):** maximizes population but publishes anonymized
  activity without explicit say-so. Inconsistent with the app's posture.
- **Opt-in / reciprocity (default-off):** you appear as a ghost only if you
  enable it; optionally you only *see* ghosts if you contribute. Smaller pool,
  consistent posture, and "show me others / I'll show as one too" is a clean,
  motivating bargain.

Recommendation: **opt-in with reciprocity.** Add `appear_in_orbit_anon` (server
`users` column + a toggle in sharing settings next to the existing card
toggles) with exact copy: "Show your commit and line counts to others as an
anonymous, unlabeled orb. No name, project, or status." Plus a client-only
`show_anon_peers` `@AppStorage` view preference to hide ghosts even when
eligible.

Reciprocity also implies: gate ghost *visibility* on the viewer having published
`git_stats` today.

## Edge cases

- Old client / new server: `ghosts` optional, ignored.
- New client / old server: `ghosts == nil` => render none.
- Numbered ghost count < 4 after the k-gate: show what exists; never pad with
  fakes.
- Reduce-motion: respected via the existing `floatOffset` guard.
- Viewer offline / no git_stats today: under reciprocity, don't show ghosts.

## Testing

- Server unit tests for `selectGhosts`: friend exclusion; k-gate (`n<8` =>
  statless, `n==0` => `[]`, `n>=8` => numbered, ≤ 4); sampling cardinality; and a
  **regression guard** asserting the serialized ghost object contains *only* the
  allowed numeric fields — no `handle` / `avatar` / `cards` keys (identity-leak
  canary).
- Isolated UI harness (CFFIXED_USER_HOME + token.dev + local relay; cfprefsd
  gotcha noted in memory) seeded with a > 8-user pool to eyeball muting / sizing
  / depth, plus a < 8 run for statless orbs.
- Snapshot the orbit at 0 / 1 / 4 real friends × {0 ghosts, statless, numbered}.

## Suggested additional improvements (off-hand)

1. **Ghosts as a growth lever, not just decor.** Pair the faint sky with low-key
   copy: "These are real developers on Vibes right now — invite someone to bring
   them into focus." Turning a distant orb into a real connection is a concrete
   reason to invite, directly attacking the 1-connection problem.
2. **Aggregate sky stat** ("47 developers shipped code today") — safe at any pool
   size, good permanent < 8 behavior and/or ship-first option. (Also listed
   above as a primary direction.)
3. **Parallax depth.** Tie ghost drift to subtle parallax so "distance" is
   conveyed by motion, not only size/opacity — sells the metaphor.
4. **List-view footer count** ("+5 others active") so list users feel population
   without the orbit treatment — keeps "orbit only" for the *visual* while not
   hiding the signal entirely. (Optional; only if it doesn't muddy the
   orbit-only intent.)
5. **Rate-limit / cache `selectGhosts`** per viewer per day — it's a
   community-wide scan; memoize alongside existing per-day aggregates rather than
   recomputing every feed poll.
6. **Audit `GHOST_MIN_POOL` against real active-user counts** before enabling
   numbered ghosts; ship aggregate + statless first if the daily pool is small.
7. **Two-person delight.** Since Vibes may be fun for just two people, make sure
   the *real* two-person orbit already feels good on its own (motion, churn ring,
   moons) so ghosts are additive, not load-bearing. Consider whether the
   two-person case wants statless orbs at all, or just a warm aggregate line.

## Next session

Pick the direction for the tiny-pool / early-network case (statless orbs vs
aggregate vs empty vs combination) and the consent model (opt-in reciprocity vs
opt-out), then turn this into an implementation-ready task breakdown
(server `selectGhosts` + serializer + tests → `FeedResponse`/`GhostPeer` →
`GhostOrbView` + background layer → settings toggle).
