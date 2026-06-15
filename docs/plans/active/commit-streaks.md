# Vibes: Commit Streaks

Status: proposed.

## Purpose

Show a small "days in a row" signal for friends who have committed code on consecutive Vibes days.

The feature should feel like ambient presence, not a productivity scoreboard. A streak says "still building" and nothing more. It should not expose repos, branches, commit messages, filenames, tools, editors, or who wrote the code.

## Recommendation

Add a server-computed `commit_streak` summary to each merged feed row:

```json
{
  "commit_streak": {
    "days": 5,
    "through_day": "2026-06-15"
  }
}
```

Rules:

- A streak day counts when the user has at least one committed change on that user's account-level Vibes day.
- The relay derives streaks from aggregate per-day stats it already receives through `git_stats`; clients do not publish a hand-authored streak value.
- The feed exposes only the current streak count and the day it runs through. It does not expose a calendar, missing days, per-device rows, repo names, or commit details.
- Streaks follow the `git_stats` sharing switch. If a user is not sharing Git stats, friends do not receive a streak.
- An explicit Offline state should not make a live streak look active. The UI may show the last known snapshot in the same way it already handles stale Git stats, but it should not add pressure copy like "lost" or "broken."

## Product Semantics

Use the account-level Vibes day timezone already defined in `spec-v2.md`.

The streak is computed against the user's own day boundary, not the viewer's day and not the relay server's clock. A friend in New York may see a California friend's streak through the California friend's Vibes day.

Today is still in progress. If the user committed today, the streak runs through today. If the user has not committed today yet but did commit yesterday, the relay can return the streak through yesterday; the client should render that quietly or omit the badge until today has activity. Do not render a warning state before the day is over.

Recommended UI copy:

```text
5 day streak
```

For one day:

```text
1 day streak
```

Avoid competitive language such as "best," "rank," "leader," "broken," or "missed."

## Current Repo State

Relevant implementation today:

- `client/Vibes/GitScanner.swift` counts committed work only, filtered by the repo's configured `user.email`, inside a `VibesDayWindow`.
- `StatusBuilder` publishes a `git_stats` card with aggregate `commits`, `files_changed`, `insertions`, `deletions`, and `repos_touched`.
- `server/src/lib/server/db.js` migration 6 created `daily_activity` with one row per `(user_id, device_id, client_day)`, but it stores only `insertions` and `deletions`.
- `server/src/lib/server/relay.js` records `daily_activity` from the latest `git_stats` card and uses it for `typical_churn`.
- `getFeed` already attaches `typical_churn` as a top-level field on each merged status. `commit_streak` can follow the same top-level pattern.

The main gap: a day with a commit but zero line churn, or a future scanner that reports commits more directly than churn, would not be visible to `daily_activity` today. Streaks need stored commit counts.

## Data Model

Append a new migration; do not edit migration 6.

```sql
ALTER TABLE daily_activity ADD COLUMN commits INTEGER NOT NULL DEFAULT 0;
```

Keep the primary key unchanged:

```sql
PRIMARY KEY (user_id, device_id, client_day)
```

Update `recordDailyActivity` so each upsert stores:

- `commits`
- `insertions`
- `deletions`
- `updated_at`

Backfill behavior:

- Existing rows get `commits = 0`.
- Old rows cannot prove a commit happened unless they had churn. Do not invent commit counts.
- For old rows with `insertions + deletions > 0`, the relay may treat the day as active for `typical_churn` only. It should not turn historical churn into fake commit counts unless we explicitly choose a compatibility mode.

Recommended v1 compatibility mode:

- Streaks start cleanly after the migration.
- This is honest and avoids overstating older history.

If preserving older streaks matters later, add a one-time backfill that treats `insertions + deletions > 0` as an active day. That backfill should be a separate decision because it changes the meaning from "committed any code" to "reported any churn."

## Server Contract

Add `commit_streak` to merged feed statuses:

```json
{
  "user": { "handle": "marcus", "display_name": "Marcus" },
  "mode": "online",
  "day": "2026-06-15",
  "updated_at": "2026-06-15T18:02:00.000Z",
  "typical_churn": 1210,
  "commit_streak": {
    "days": 5,
    "through_day": "2026-06-15"
  },
  "cards": []
}
```

Return `commit_streak: null` when:

- the merged row has no `git_stats` card;
- Git stats sharing is off;
- there is no active day in `daily_activity`;
- the user has no status rows.

Keep `commit_streak` outside the opaque `cards` array. It is a relay-derived summary, similar to `typical_churn`, and the client benefits from a typed field instead of parsing a generic card.

## Streak Algorithm

Add a relay helper:

```js
commitStreak(db, userId, currentDay)
```

Suggested query shape:

1. Group `daily_activity` by `client_day`.
2. Sum `commits` across devices.
3. Keep days where `SUM(commits) > 0`.
4. Walk backward from the newest active day that is either `currentDay` or before it.
5. Count consecutive calendar days with activity.

Calendar walking should use the user's account timezone model. Since `client_day` is already a `YYYY-MM-DD` Vibes-day string, the helper can subtract one Gregorian day from the day string. It does not need to expose or return timezone data.

Details:

- Multiple devices on the same day count as one streak day.
- Duplicate repos across devices are not deduplicated; this matches the current `git_stats` v1 choice.
- Future-dated client days should be ignored if they are after the user's current Vibes day.
- A day with commits but zero insertions/deletions counts.
- A day with churn but zero commits does not count for the clean v1 streak.

## Client UX

Add an optional `commitStreak` field to `MergedStatus`.

```swift
struct CommitStreak: Codable, Equatable {
  var days: Int
  var throughDay: String
}
```

Render it as a small text chip near the existing commit count in `FriendCard` and the compact status label in `OrbitView`.

Suggested placement:

- `FriendCard.legend`: after the "N commits today" text, if `days >= 2`.
- `OrbitView`: in the small person label only when there is room, also gated on `days >= 2`.
- Do not show streaks in empty, setup, settings, or invite surfaces.

Use plain text. No emoji, no flames, no trophy language.

Initial display rules:

- Hide `commit_streak` for `days < 2`; "1 day streak" adds clutter and feels like a metric.
- Show "2 day streak" or "5 day streak" for online or stale rows with visible Git stats.
- If the row is explicit Offline and the product later hides old Git cards there, hide the streak with them.

## Privacy

Streaks are derived from data Vibes already shares when `git_stats` is enabled, but they add server-side history. Keep the stored and returned data narrow:

- Store only daily aggregate commit counts per user, device, and Vibes day.
- Do not store commit hashes, messages, branches, filenames, authors beyond the existing local `user.email` filter, repo paths, or raw aliases in the streak table.
- Return only `days` and `through_day`.
- Do not expose per-day history through `/api/feed`.
- Admin detail may show enough to debug, but it should stay aggregate and omit repo details.

## Implementation Plan

### Phase 1: Server History

- Append the `daily_activity.commits` migration.
- Update `recordDailyActivity` to persist `commits`.
- Keep `typicalChurn` behavior unchanged.
- Add tests that `upsertStatus` records commit counts for each device/day.

Acceptance:

- Existing databases migrate cleanly.
- Publishing a `git_stats` card writes `commits` into `daily_activity`.
- Old rows with no commit count do not produce fake streaks.

### Phase 2: Feed Streak Summary

- Add `commitStreak(db, userId, currentDay)`.
- Call it from `getFeed` for each merged status.
- Only attach a streak when the merged status includes visible `git_stats`.
- Update `shared/contract/feed-response.json`.

Acceptance:

- Consecutive active days return the expected count.
- A gap resets the count.
- Two devices on one day count as one day.
- Future client days are ignored.
- Feed JSON exposes no per-day history.

### Phase 3: Client Decode and Display

- Add `CommitStreak` and `MergedStatus.commitStreak`.
- Render a small streak label next to the commit count in `FriendCard`.
- Add a compact rendering path in `OrbitView` only if the text fits cleanly.
- Update previews and fixture decode tests.

Acceptance:

- Old relays without `commit_streak` decode cleanly.
- Rows with no streak look exactly as they do today.
- Rows with a streak show a quiet text label with no layout jump.

### Phase 4: Docs and Runbooks

- Update `spec-v2.md` to mention commit streaks under Local Git Stats.
- Update `docs/client-runbook.md` if the feed UI map changes.
- Update `docs/server-runbook.md` with the new migration and aggregate history note.

Acceptance:

- The product spec names the privacy boundary.
- The runbooks describe the aggregate-only server history.

## Test Plan

Server:

- Migration adds `daily_activity.commits`.
- `recordDailyActivity` stores commits from `git_stats`.
- `commitStreak` returns 0/null when there is no active day.
- Consecutive days across one device produce the right count.
- Consecutive days across multiple devices still count by day, not by device.
- A skipped day resets the streak.
- A zero-churn commit day counts when `commits > 0`.
- A churn-only legacy day with `commits = 0` does not count.
- `/api/feed` returns `commit_streak` only when `git_stats` is visible.

Client:

- Decode feed fixtures with and without `commit_streak`.
- `FriendCard` renders the streak label for `days >= 2`.
- `FriendCard` hides the label for nil, zero, and one-day streaks.
- Long display names and repo aliases still fit with the added label.

Manual proof:

- Seed a user with three consecutive `daily_activity` rows and one friend relationship; `/api/feed` returns `days: 3`.
- Add a gap day and verify the streak resets.
- Run the macOS app or previews and capture the feed with a streak label visible.

## Non-Goals

- Leaderboards.
- Longest streaks.
- Streak repair.
- Calendar heatmaps.
- Push reminders to commit.
- Comparing friends by streak.
- Repo-level streaks.
- Public streak pages.

## Open Questions

1. Should a streak through yesterday render for friends when today has no commit yet, or should the UI wait until the user commits today?
2. Should the user be able to hide streaks separately from `git_stats`, or is the existing Git stats sharing switch enough for v1?
3. Should admin detail expose aggregate streak debugging, or should `/api/feed` be the only surfaced path until someone needs it?
