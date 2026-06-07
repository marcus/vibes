#!/usr/bin/env node
// Seed a dev database with realistic data for exercising the admin area.
// Usage: VIBES_DB_PATH=data/dev.sqlite node scripts/seed-admin-dev.mjs
import { openDb } from "../src/lib/server/db.js";
import {
  acceptInvite,
  createInvite,
  createToken,
  createUser,
  revokeInvite,
  upsertStatus,
} from "../src/lib/server/relay.js";

const db = openDb(process.env.VIBES_DB_PATH ?? "data/dev.sqlite");
const day = new Date().toISOString().slice(0, 10);

function status(user, deviceId, mode, label, extra = {}) {
  upsertStatus(db, user, {
    device_id: deviceId,
    device_label: label,
    mode,
    day,
    updated_at: new Date(Date.now() - (extra.ageMin ?? 4) * 60_000).toISOString(),
    manual_status: extra.manual ?? null,
    derived_status: extra.derived ?? "vibing",
    cards:
      mode === "broadcasting"
        ? [
            {
              type: "git_stats",
              enabled: true,
              summary: "3 repos touched - 7 commits - +812 / -140 LOC",
              data: {
                commits: 7,
                files_changed: 24,
                insertions: 812,
                deletions: 140,
                uncommitted_insertions: 12,
                uncommitted_deletions: 3,
                repos_touched: 3,
              },
            },
          ]
        : [],
  });
}

// Founder + a friend graph built through invites.
const marcus = createUser(db, { handle: "marcus", displayName: "Marcus Vorwaller" });
createToken(db, marcus.id, "MacBook Pro");
createToken(db, marcus.id, "Mac mini");
status(marcus, "marcus-mbp", "broadcasting", "MacBook Pro", { manual: "wiring up the admin area", ageMin: 2 });
status(marcus, "marcus-mini", "quiet", "Mac mini", { ageMin: 50 });

const inviteKen = createInvite(db, marcus.id);
const ken = createUser(db, { handle: "ken", displayName: "Ken Norton" });
acceptInvite(db, inviteKen.code, { acceptingUserId: ken.id });
createToken(db, ken.id, "Ken MBP");
status(ken, "ken-1", "broadcasting", "Ken MBP", { manual: "refactoring the scanner", ageMin: 9 });

const inviteSam = createInvite(db, marcus.id);
const sam = createUser(db, { handle: "sam", displayName: "Sam Rivera" });
acceptInvite(db, inviteSam.code, { acceptingUserId: sam.id });
status(sam, "sam-1", "quiet", "Sam Air", { ageMin: 120 });

const inviteAvery = createInvite(db, ken.id);
const avery = createUser(db, { handle: "avery", displayName: "Avery Chen" });
acceptInvite(db, inviteAvery.code, { acceptingUserId: avery.id });
// Avery stays offline (no status) and disabled.
db.prepare("UPDATE users SET disabled_at = ? WHERE id = ?").run(new Date().toISOString(), avery.id);

createUser(db, { handle: "jordan", displayName: "Jordan Blake" });

// A spread of invite states for the invites view.
createInvite(db, marcus.id); // open
const revoked = createInvite(db, marcus.id);
revokeInvite(db, marcus.id, revoked.id); // revoked
const expired = createInvite(db, sam.id);
db.prepare("UPDATE invites SET expires_at = ? WHERE id = ?").run("2020-01-01T00:00:00.000Z", expired.id); // expired

console.log(JSON.stringify({ ok: true, users: db.prepare("SELECT COUNT(*) n FROM users").get().n, marcus: marcus.id }, null, 2));
