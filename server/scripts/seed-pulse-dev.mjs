#!/usr/bin/env node
// Seed a dev database with global git activity so the Network Pulse renders.
// The pulse aggregates ALL users (not just friends), so once this runs any
// account on the relay sees the numbered core — even with zero friends.
//
// Usage: VIBES_DB_PATH=data/dev.sqlite node scripts/seed-pulse-dev.mjs
import { openDb } from "../src/lib/server/db.js";
import { createToken, createUser } from "../src/lib/server/relay.js";

const dbPath = process.env.VIBES_DB_PATH ?? "data/dev.sqlite";
const db = openDb(dbPath);

// Which columns daily_activity actually has (commits was added by a later
// migration) so the INSERT matches the live schema.
const cols = new Set(db.prepare(`PRAGMA table_info(daily_activity)`).all().map((c) => c.name));
const hasCommits = cols.has("commits");

const day = (offset) =>
  new Date(Date.now() - offset * 86_400_000).toISOString().slice(0, 10);
const isWeekend = (iso) => [0, 6].includes(new Date(`${iso}T12:00:00Z`).getUTCDay());

const people = [
  { handle: "rema", name: "Rema" },
  { handle: "jonas", name: "Jonas" },
  { handle: "priya", name: "Priya" },
  { handle: "tomo", name: "Tomo" },
  { handle: "elise", name: "Elise" },
];

const users = people.map((p) => {
  try {
    return createUser(db, { handle: p.handle, displayName: p.name });
  } catch {
    return db.prepare(`SELECT id, handle FROM users WHERE handle = ?`).get(p.handle);
  }
});

const insertRow = db.prepare(
  hasCommits
    ? `INSERT INTO daily_activity (user_id, device_id, client_day, commits, insertions, deletions, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, ?)
       ON CONFLICT(user_id, device_id, client_day) DO UPDATE SET
         commits = excluded.commits, insertions = excluded.insertions,
         deletions = excluded.deletions, updated_at = excluded.updated_at`
    : `INSERT INTO daily_activity (user_id, device_id, client_day, insertions, deletions, updated_at)
       VALUES (?, ?, ?, ?, ?, ?)
       ON CONFLICT(user_id, device_id, client_day) DO UPDATE SET
         insertions = excluded.insertions, deletions = excluded.deletions,
         updated_at = excluded.updated_at`,
);

// Deterministic-ish pseudo amounts so reruns are stable but varied.
const amount = (seed, base) => base + ((seed * 2654435761) % base);

let rows = 0;
for (let offset = 13; offset >= 0; offset--) {
  const iso = day(offset);
  // Contributors per day: weekdays busy (4-5), most weekends quiet — and two
  // weekend days deliberately drop to 2 so the k>=3 suppression shows as gaps.
  let count;
  if (offset === 0) count = 5; // today: solid, numbered, biggest day (laps)
  else if (isWeekend(iso)) count = offset % 4 === 0 ? 2 : 3;
  else count = 4 + (offset % 2);

  for (let u = 0; u < count; u++) {
    const user = users[u];
    const seed = offset * 7 + u * 13;
    const weekendScale = isWeekend(iso) ? 0.4 : 1;
    // Make today a big network day so churn > median and the lap badge appears.
    const todayBoost = offset === 0 ? 3.4 : 1;
    const ins = Math.round(amount(seed, 1800) * weekendScale * todayBoost);
    const del = Math.round(amount(seed + 5, 600) * weekendScale * todayBoost);
    const updatedAt = new Date(Date.now() - offset * 86_400_000).toISOString();
    const args = hasCommits
      ? [user.id, "seed-dev", iso, 3 + (seed % 9), ins, del, updatedAt]
      : [user.id, "seed-dev", iso, ins, del, updatedAt];
    insertRow.run(...args);
    rows++;
  }
}

// A ready-to-use viewer token so you can verify the feed without registering.
const viewer = users[0];
const { token } = createToken(db, viewer.id, "pulse-dev-viewer");

console.log(`Seeded ${rows} daily_activity rows across ${users.length} users into ${dbPath}.`);
console.log(`commits column present: ${hasCommits}`);
console.log(`Viewer token (user @${viewer.handle}):`);
console.log(token);
