# Vibes: Multi-Device Aggregation & Timezones

Status: implemented (moved from active 2026-08-21; migration 3 `user_timezone`).

## Purpose

Make Vibes behave clearly when one person runs it on more than one Mac, including when those Macs are in different time zones or one machine has stale data.

Today the relay stores one latest status row per `(user_id, device_id)` and merges those rows on feed read. That is the right shape, but the day boundary is weak: each client publishes a `client_day` based on that Mac's local calendar. The relay currently sums Git stats only for broadcasting devices whose `client_day` equals the newest broadcasting device's day. If a laptop and desktop disagree about "today," one machine's stats disappear from the merged view.

## Recommendation

Use a **user-level Vibes day timezone**.

Each user has one IANA timezone string, for example `America/Los_Angeles`. All of that user's devices compute the same "today" window from that timezone, scan Git activity since that user's Vibes-day midnight, and publish the same `day` value. Friends in other time zones still see that person against that person's own Vibes day.

Why this is the right v1 tradeoff:

- It matches the product question: "What is Marcus doing today?" not "What is today for my viewer?"
- It keeps one person's laptop and desktop aggregating cleanly even if one Mac travels or has a different system timezone.
- It avoids UTC day boundaries, which are technically neat but feel wrong for late-night coding friends.
- It makes cross-time-zone friend groups understandable: each row is a person's local-ish day, not a forced global scoreboard day.
- It is easy to explain in first-run copy: "Vibes uses one day boundary for all your Macs."

Do not use a viewer-timezone day for v1. That would make a friend's totals change depending on who is looking. Do not use the relay server timezone. That would leak infrastructure into the product. UTC can remain a fallback for invalid/missing timezone data, not the product model.

## Product Semantics

- A user's Git stats represent their **current Vibes day**.
- A user's Vibes day is based on the timezone stored on the user/account, not each device.
- A user in New York and a user in California may be on different Vibes days for a few hours. That is okay; each row is about that person.
- If one user's two devices are in different time zones, they still scan and publish the same Vibes day.
- The feed should not make time zones prominent. At most, detail copy can say "today in Marcus's timezone" if a mismatch would otherwise feel confusing.
- Feed detail should not show timezone copy in v1.
- Device rows from older Vibes days should not contribute to today's Git totals, but they can still influence "last seen" once presence becomes recency-based.

## Current Behavior

Server:

- `statuses` has `client_day TEXT NOT NULL` and latest status rows keyed by `(user_id, device_id)` in [db.js](../../../server/src/lib/server/db.js).
- `normalizeStatusPayload` validates `day` / `client_day` as `YYYY-MM-DD` and stores it unchanged in [relay.js](../../../server/src/lib/server/relay.js).
- `mergeUserStatuses` picks `latestDay = broadcasting[0]?.client_day ?? source.client_day`.
- `mergeGitStats(rows, latestDay)` sums only rows where `row.mode === "broadcasting"` and `row.client_day === latestDay`.

Client:

- `StatusBuilder.payload` sends `day: localDay(now)` in [GitScanner.swift](../../../client/Vibes/GitScanner.swift).
- `localDay` uses `Calendar.current`, so the day follows that Mac's current system timezone.
- The Git scanner uses `git log --since=midnight`, which also follows the local system environment rather than an account-wide timezone.

## Goals

- Add a user/account timezone and use it for all devices owned by that user.
- Make multi-device Git stats aggregate across all broadcasting devices for the user's current Vibes day.
- Fix the "today mismatch" caveat directly; do not leave it as a known limitation.
- Keep cross-time-zone friend groups natural: each friend row uses that friend's Vibes day.
- Keep privacy defaults: no repo paths, branch names, commit messages, filenames, editor/process details, code-origin attribution, or transcripts.
- Keep the relay dumb. The relay can validate and merge; the client owns local Git scanning.

## Non-Goals

- A global leaderboard or globally normalized day.
- Per-friend timezone display in the main feed.
- Historical graphs or status history.
- Automatic travel detection with prompts.
- Calendar/date localization polish beyond the data model needed here.
- Presence recency/online rewrite, except for making sure the data shape does not block it.

## Data Model

### User Timezone

Add a user-level timezone:

```sql
ALTER TABLE users ADD COLUMN timezone TEXT;
```

Rules:

- Store an IANA timezone identifier such as `America/Los_Angeles`.
- New registration should accept `timezone` and default to the client's `TimeZone.current.identifier`.
- Existing users can get `timezone = NULL` until their next app publish or profile update; the server falls back to `UTC` only when needed.
- If a legacy account has no timezone and upgraded device statuses disagree, the server chooses the newest valid device timezone once and persists it.
- Later profile/settings UI can expose this as "Vibes day timezone." V1 does not add editable timezone settings.

### Status Payload

Extend the status payload without breaking old clients:

```json
{
  "day": "2026-06-08",
  "day_timezone": "America/Los_Angeles",
  "day_start_at": "2026-06-08T07:00:00.000Z",
  "day_end_at": "2026-06-09T07:00:00.000Z"
}
```

Rules:

- `day` remains the canonical merge key.
- `day_timezone` identifies the timezone used to compute `day`.
- `day_start_at` and `day_end_at` are UTC instants for debugging, tests, and future UI. They also make DST behavior explicit.
- The relay validates shape but does not trust the payload to change account ownership or friend visibility.
- If old clients omit the new fields, preserve existing behavior for that status row, but prefer upgraded rows for aggregation once available.

### Config

Add a client config value:

```json
{
  "identity": {
    "handle": "marcus",
    "display_name": "Marcus",
    "timezone": "America/Los_Angeles"
  }
}
```

Client rules:

- Missing timezone is preserved as missing in imported config; publishing falls back locally to `TimeZone.current.identifier` when no account timezone is available.
- Existing-account setup uses the account timezone returned by the relay where possible.
- A device should not silently change the account timezone just because the Mac's system timezone changes.
- Registration and imported config are the v1 places where the client supplies or preserves an account timezone.

## Aggregation Rules

### Day Choice

For a user with status rows:

1. Prefer the current Vibes day computed from the user's account timezone at feed-read time.
2. If no broadcasting row exists for that day, fall back to the latest broadcasting row's `client_day`.
3. If there are no broadcasting rows, use the newest row only for presence/last-seen semantics.

This keeps today's active devices summed while still showing something sensible if all devices are stale.

### Git Stats

- Sum `git_stats` across broadcasting devices whose `client_day` equals the chosen Vibes day.
- Do not require the exact same `day_start_at` unless the account timezone changed mid-day. If it did, prefer rows matching the current account timezone and current day.
- If two devices publish the same repo alias, count both devices' stats as-is for v1. Cross-device duplicate repo deduplication is out of scope because it risks needing repo identity data we do not want to share.

### Singleton Cards

- `manual_status`, `derived_status`, `repo_aliases`, `spotify`, and `weather` still come from one source row: the newest broadcasting row for the chosen Vibes day.
- If there is no broadcasting row for the chosen day, use the newest broadcasting row as stale display only.
- Repo aliases are not cross-device merged in v1; they continue to come from the newest source device for the chosen day.

### Last Seen / Recency

Presence rework should compute last seen from the newest status activity across all devices, not only same-day devices.

That means a device from yesterday can still explain "last seen 8h ago," but it must not inflate today's Git stats.

## Timezone Recommendation Details

### Why User Timezone, Not Device Timezone

Device timezone is exactly what creates the current bug. If a user has a laptop in New York and a desktop in California, local-midnight scans describe two different windows. The account needs one day boundary.

### Why User Timezone, Not Viewer Timezone

Viewer timezone makes the same person appear to have different totals depending on who is looking. That feels like a dashboard, not a shared presence app.

### Why Not UTC

UTC is stable but user-hostile for late-night coding. A user in California would reset at 4pm/5pm depending on daylight saving time. Vibes should feel ambient and human, not infrastructure-shaped.

### Travel Behavior

Default behavior: keep the account timezone stable. If a user travels, Vibes still uses their chosen Vibes day until they change it. Later, settings can offer:

```text
Vibes day timezone
America/Los_Angeles
Use this for all your Macs
```

Do not auto-update this value from a traveling laptop without asking.

## Implementation Plan

### Phase 1: Contract and Schema

- Add a migration that appends `timezone TEXT` to `users`.
- Update public user/account serialization to include timezone where appropriate.
- Update `POST /api/register` to accept `timezone`.
- Validate timezone identifiers on the server. Accept IANA-style strings present in `Intl.supportedValuesOf("timeZone")` when available; otherwise accept conservative `Area/Name` strings and fall back safely.
- Add contract fixtures for status payloads with `day_timezone`, `day_start_at`, and `day_end_at`.

### Phase 2: Client Day Window

- Add `timezone` to `IdentityConfig` or a nearby account config type.
- On first launch/register, send `TimeZone.current.identifier`.
- Replace `localDay(now)` with `vibesDay(now, timezone:)`.
- Replace `git log --since=midnight` with an explicit ISO/date argument derived from `day_start_at`.
- Keep working tree and staged diff behavior unchanged; they are current snapshots, not date-scoped history.
- Publish `day_timezone`, `day_start_at`, and `day_end_at` in `StatusPayload`.

### Phase 3: Relay Merge

- Teach `normalizeStatusPayload` to accept optional day-boundary fields and preserve them in `payload_json`.
- Update `mergeUserStatuses` to choose the account's current Vibes day when `user.timezone` is known.
- Update `getFeed` status user queries to include user timezone.
- Update `mergeGitStats` tests for:
  - two devices same account timezone, same Vibes day, stats sum;
  - two devices different local/system time zones but same account day, stats sum;
  - stale older-day device does not contribute to today's Git stats;
  - latest stale device can still affect last-seen once presence recency lands.

### Phase 4: Setup and Multi-Machine Copy

- First-run copy should include:

```text
Already using Vibes on another Mac?
Use the same account token on both Macs. Vibes uses one day boundary for all your Macs, so today's Git stats combine cleanly.
```

- Existing-token import should preserve the account timezone if exported, and hydrate it from `/api/me` when the relay has one.
- If the app cannot fetch account timezone yet, use local config and avoid changing server timezone implicitly.

### Phase 5: Admin and Docs

- Admin user detail can show account timezone and per-device status day/timezone for debugging.
- Update `spec-v2.md` and server/client runbooks with the user-level timezone model.
- Remove the old caveat that off-day machines are dropped due to timezone mismatch; replace it with the stale-row behavior.

## Test Plan

Server:

- `registerUser` stores a valid timezone.
- Invalid timezone is rejected or normalized to a safe default.
- `upsertStatus` accepts new day-boundary fields.
- Feed merge sums same account-day device rows.
- Feed merge excludes stale previous-day Git stats.
- Feed merge does not expose device IDs, device labels, raw paths, branch names, commit messages, filenames, agent/tool attribution, or transcripts.

Client:

- Day calculation for `America/Los_Angeles` around midnight.
- Day calculation across DST transition dates.
- Git scanner uses the explicit start instant rather than system-local `midnight`.
- Existing config without timezone loads without inventing one, then publishes using a Mac-timezone fallback if the relay cannot provide an account timezone.

Manual proof:

- Configure two local statuses for the same user with two device IDs and the same account day; feed shows summed commits/LOC.
- Configure a stale previous-day row; feed excludes it from Git totals.
- Change the test account timezone and verify the computed day boundary changes predictably.

## Decisions

- Account timezone is not editable in v1 settings. It is set during registration/import, with future settings UI left for later.
- Feed detail does not show timezone copy.
- If account timezone is missing and devices disagree, the server chooses the newest valid device timezone once and persists it.
- Repo aliases continue to come from the newest source device for the chosen day. Cross-device alias merge/dedupe can wait until real users hit the long-running different-name edge case.
