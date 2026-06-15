import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { existsSync, mkdtempSync, readFileSync, rmSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { fileURLToPath } from "node:url";
import { migrate, openDb } from "../src/lib/server/db.js";
import { checkRateLimit, readJson } from "../src/lib/server/http.js";
import { getAvatarStore, resetAvatarStore } from "../src/lib/server/avatarStore.js";
import {
  HOUSE_STYLE,
  RelayError,
  acceptInvite,
  authenticateToken,
  avatarGradientFor,
  avatarUrlFor,
  claimDeviceLinkCode,
  clearUserAvatar,
  createDeviceLinkCode,
  createInvite,
  createToken,
  createUser,
  deriveHandleBase,
  getFeed,
  getInviteByCode,
  inviteState,
  listInvites,
  listTokens,
  mintDeviceToken,
  newShortId,
  registerUser,
  removeFriend,
  revokeInvite,
  revokeToken,
  setUserAvatar,
  setUserGradient,
  typicalChurn,
  upsertStatus,
  validateHexColor,
  validatePng,
} from "../src/lib/server/relay.js";

/**
 * Smallest bytes that pass validatePng: the 8-byte signature followed by an
 * IHDR chunk whose width/height live at offsets 16 and 20. We do not need a
 * decodable image, only valid signature + IHDR dimensions.
 */
function fakePng(width = 512, height = 512) {
  const buf = Buffer.alloc(33);
  Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]).copy(buf, 0);
  buf.writeUInt32BE(13, 8); // IHDR length
  buf.write("IHDR", 12, "ascii");
  buf.writeUInt32BE(width, 16);
  buf.writeUInt32BE(height, 20);
  return buf;
}

/** @type {import('better-sqlite3').Database} */
let db;

beforeEach(() => {
  db = openDb(":memory:");
});

function fixture(name) {
  return JSON.parse(
    readFileSync(
      fileURLToPath(new URL(`../../shared/contract/${name}.json`, import.meta.url)),
      "utf8",
    ),
  );
}

function expectRelayError(fn, code, status) {
  try {
    fn();
    throw new Error("Expected RelayError");
  } catch (err) {
    expect(err).toBeInstanceOf(RelayError);
    expect(err.code).toBe(code);
    if (status) expect(err.status).toBe(status);
  }
}

describe("migrations", () => {
  it("creates the core tables and timezone column", () => {
    const tables = db
      .prepare("SELECT name FROM sqlite_master WHERE type = 'table'")
      .all()
      .map((row) => row.name);
    for (const t of ["users", "auth_tokens", "friendships", "invites", "statuses"]) {
      expect(tables).toContain(t);
    }
    const columns = db.prepare("PRAGMA table_info(users)").all().map((row) => row.name);
    expect(columns).toContain("timezone");
  });

  it("applies migration v4 (avatars table + users.avatar_id)", () => {
    const tables = db
      .prepare("SELECT name FROM sqlite_master WHERE type = 'table'")
      .all()
      .map((row) => row.name);
    expect(tables).toContain("avatars");

    const userColumns = db.prepare("PRAGMA table_info(users)").all().map((row) => row.name);
    expect(userColumns).toContain("avatar_id");

    const avatarColumns = db.prepare("PRAGMA table_info(avatars)").all().map((row) => row.name);
    for (const c of ["id", "user_id", "store", "content_type", "width", "height", "byte_size", "prompt", "style", "created_at"]) {
      expect(avatarColumns).toContain(c);
    }

    const versions = db
      .prepare("SELECT version FROM schema_migrations")
      .all()
      .map((row) => row.version);
    expect(versions).toContain(4);
  });

  it("applies migration v5 (avatar_kind + gradient columns)", () => {
    const userColumns = db.prepare("PRAGMA table_info(users)").all().map((row) => row.name);
    for (const c of ["avatar_kind", "avatar_gradient_start", "avatar_gradient_end"]) {
      expect(userColumns).toContain(c);
    }

    const versions = db
      .prepare("SELECT version FROM schema_migrations")
      .all()
      .map((row) => row.version);
    expect(versions).toContain(5);
  });

  it("is idempotent when run again", () => {
    const before = db.prepare("SELECT count(*) AS n FROM schema_migrations").get().n;
    expect(before).toBeGreaterThan(0);
    expect(() => migrate(db)).not.toThrow();
    const after = db.prepare("SELECT count(*) AS n FROM schema_migrations").get().n;
    expect(after).toBe(before);
  });

  it("applies migration v6 (daily_activity table)", () => {
    const tables = db
      .prepare("SELECT name FROM sqlite_master WHERE type = 'table'")
      .all()
      .map((row) => row.name);
    expect(tables).toContain("daily_activity");
    expect(tables).toContain("daily_commits");

    const columns = db.prepare("PRAGMA table_info(daily_activity)").all().map((row) => row.name);
    for (const c of ["user_id", "device_id", "client_day", "commits", "insertions", "deletions", "updated_at"]) {
      expect(columns).toContain(c);
    }
    const commitColumns = db.prepare("PRAGMA table_info(daily_commits)").all().map((row) => row.name);
    for (const c of ["user_id", "client_day", "commit_id", "files_changed", "insertions", "deletions", "committed_at", "updated_at"]) {
      expect(commitColumns).toContain(c);
    }
  });
});

describe("users", () => {
  it("derives stable handle bases from display names", () => {
    expect(deriveHandleBase("  Dána Scully!!  ")).toBe("dana-scully");
    expect(deriveHandleBase("你好")).toBe("friend");
    expect(deriveHandleBase("a".repeat(80))).toHaveLength(32);
  });

  it("rejects a duplicate handle", () => {
    createUser(db, { handle: "marcus", displayName: "Marcus" });
    expect(() => createUser(db, { handle: "marcus", displayName: "Marc" })).toThrow(
      RelayError,
    );
  });

  it("treats handles case-insensitively", () => {
    createUser(db, { handle: "Marcus", displayName: "Marcus" });
    expect(() => createUser(db, { handle: "marcus", displayName: "M" })).toThrow(
      RelayError,
    );
  });

  it("rejects handles that are awkward in invite URLs or setup files", () => {
    expect(() => createUser(db, { handle: "mar cus", displayName: "Marcus" })).toThrow(
      RelayError,
    );
  });

  it("registerUser creates user and token together", () => {
    const { user, token } = registerUser(db, {
      displayName: "Dana Scully",
      deviceLabel: "Dana MacBook",
      timezone: "America/Los_Angeles",
    });

    expect(user.handle).toBe("dana-scully");
    expect(user.timezone).toBe("America/Los_Angeles");
    expect(token.token).toBeTruthy();
    expect(authenticateToken(db, token.token).user.id).toBe(user.id);
    expect(db.prepare("SELECT COUNT(*) AS n FROM users").get().n).toBe(1);
    expect(db.prepare("SELECT COUNT(*) AS n FROM auth_tokens").get().n).toBe(1);
  });

  it("registerUser derives unique handles from duplicate display names", () => {
    const first = registerUser(db, { displayName: "Dana" });
    const second = registerUser(db, { displayName: "Dana" });

    expect(first.user.handle).toBe("dana");
    expect(second.user.handle).toBe("dana-2");
  });

  it("registerUser keeps suffixed handles within the handle limit", () => {
    const name = "Dana " + "A".repeat(50);
    const first = registerUser(db, { displayName: name });
    const second = registerUser(db, { displayName: name });

    expect(first.user.handle).toHaveLength(32);
    expect(second.user.handle).toHaveLength(32);
    expect(second.user.handle.endsWith("-2")).toBe(true);
  });

  it("registerUser rejects invalid display names without creating a token", () => {
    expectRelayError(
      () => registerUser(db, { displayName: "   ", deviceLabel: "MacBook" }),
      "invalid_display_name",
      400,
    );
    expect(db.prepare("SELECT COUNT(*) AS n FROM users").get().n).toBe(0);
    expect(db.prepare("SELECT COUNT(*) AS n FROM auth_tokens").get().n).toBe(0);
  });

  it("registerUser rejects invalid timezone identifiers", () => {
    expectRelayError(
      () => registerUser(db, { displayName: "Dana", timezone: "California" }),
      "invalid_timezone",
      400,
    );
    expect(db.prepare("SELECT COUNT(*) AS n FROM users").get().n).toBe(0);
  });
});

describe("auth", () => {
  it("authenticates a raw bearer token without storing it", () => {
    const user = createUser(db, { handle: "marcus", displayName: "Marcus" });
    const token = createToken(db, user.id, "MacBook");

    const auth = authenticateToken(db, token.token);
    expect(auth.user.handle).toBe("marcus");

    const stored = db.prepare("SELECT token_hash FROM auth_tokens WHERE id = ?").get(token.id);
    expect(stored.token_hash).not.toContain(token.token);
  });

  it("rejects a revoked token", () => {
    const user = createUser(db, { handle: "marcus", displayName: "Marcus" });
    const token = createToken(db, user.id, "MacBook");
    revokeToken(db, user.id, token.id);
    expect(() => authenticateToken(db, token.token)).toThrow(RelayError);
  });
});

describe("invites", () => {
  it("accepts an open invite by linking existing users", () => {
    const creator = createUser(db, { handle: "marcus", displayName: "Marcus" });
    const friend = createUser(db, { handle: "ken", displayName: "Ken" });
    const invite = createInvite(db, creator.id);

    const accepted = acceptInvite(db, invite.code, { acceptingUserId: friend.id });

    expect(accepted.inviter.handle).toBe("marcus");
    expect(accepted.friend.handle).toBe("ken");

    const links = db
      .prepare("SELECT user_id, friend_user_id FROM friendships")
      .all();
    expect(links).toHaveLength(2);

    const stored = getInviteByCode(db, invite.code);
    expect(inviteState(stored)).toBe("accepted");
  });

  it("requires an existing accepting user", () => {
    const creator = createUser(db, { handle: "marcus", displayName: "Marcus" });
    const invite = createInvite(db, creator.id);

    expectRelayError(
      () => acceptInvite(db, invite.code, { acceptingUserId: "missing-user" }),
      "not_found",
      404,
    );
    expect(inviteState(getInviteByCode(db, invite.code))).toBe("open");
    expect(db.prepare("SELECT count(*) AS n FROM friendships").get().n).toBe(0);
  });

  it("never stores raw invite codes or raw tokens", () => {
    const creator = createUser(db, { handle: "marcus", displayName: "Marcus" });
    const invite = createInvite(db, creator.id);
    const { token } = registerUser(db, {
      displayName: "Ken",
      deviceLabel: "Ken MacBook",
    });

    const storedInvite = getInviteByCode(db, invite.code);
    const storedToken = db
      .prepare("SELECT token_hash FROM auth_tokens WHERE id = ?")
      .get(token.id);

    expect(storedInvite.code_hash).not.toContain(invite.code);
    expect(storedToken.token_hash).not.toContain(token.token);
  });

  it("rejects a second acceptance of the same invite", () => {
    const creator = createUser(db, { handle: "marcus", displayName: "Marcus" });
    const ken = createUser(db, { handle: "ken", displayName: "Ken" });
    const sam = createUser(db, { handle: "sam", displayName: "Sam" });
    const invite = createInvite(db, creator.id);
    acceptInvite(db, invite.code, { acceptingUserId: ken.id });
    expectRelayError(
      () => acceptInvite(db, invite.code, { acceptingUserId: sam.id }),
      "invite_unusable",
      410,
    );
  });

  it("rejects accepting your own invite", () => {
    const creator = createUser(db, { handle: "marcus", displayName: "Marcus" });
    const invite = createInvite(db, creator.id);

    expectRelayError(
      () => acceptInvite(db, invite.code, { acceptingUserId: creator.id }),
      "invite_self",
      400,
    );
    expect(inviteState(getInviteByCode(db, invite.code))).toBe("open");
  });

  it("is idempotent for already-friends users without duplicating rows", () => {
    const creator = createUser(db, { handle: "marcus", displayName: "Marcus" });
    const friend = createUser(db, { handle: "ken", displayName: "Ken" });
    const createdAt = "2026-06-06T18:00:00.000Z";
    const link = db.prepare(
      `INSERT INTO friendships (user_id, friend_user_id, state, created_at)
       VALUES (?, ?, 'accepted', ?)`,
    );
    link.run(creator.id, friend.id, createdAt);
    link.run(friend.id, creator.id, createdAt);
    const invite = createInvite(db, creator.id);

    acceptInvite(db, invite.code, { acceptingUserId: friend.id });

    expect(db.prepare("SELECT count(*) AS n FROM friendships").get().n).toBe(2);
    expect(inviteState(getInviteByCode(db, invite.code))).toBe("accepted");
  });

  it("lists invite state without reconstructing the raw invite URL", () => {
    const creator = createUser(db, { handle: "marcus", displayName: "Marcus" });
    const invite = createInvite(db, creator.id);
    const listed = listInvites(db, creator.id);

    expect(listed[0]).toMatchObject({
      id: invite.id,
      invite_url: null,
      state: "open",
      accepted_by: null,
    });
  });

  it("revokes an invite created by the caller", () => {
    const creator = createUser(db, { handle: "marcus", displayName: "Marcus" });
    const invite = createInvite(db, creator.id);
    revokeInvite(db, creator.id, invite.id);
    expect(inviteState(getInviteByCode(db, invite.code))).toBe("revoked");
  });

  it("reports an unknown code as unusable", () => {
    expect(getInviteByCode(db, "nope")).toBeUndefined();
    const user = createUser(db, { handle: "ken", displayName: "Ken" });
    expectRelayError(
      () => acceptInvite(db, "nope", { acceptingUserId: user.id }),
      "invite_unusable",
      410,
    );
  });
});

describe("device link codes", () => {
  it("creates a code and claims it for a fresh per-device token", () => {
    const user = createUser(db, { handle: "marcus", displayName: "Marcus", timezone: "America/Los_Angeles" });
    const link = createDeviceLinkCode(db, user.id);

    expect(link.code).toMatch(/^[A-Z2-9]{4}-[A-Z2-9]{4}$/);
    expect(Date.parse(link.expires_at)).toBeGreaterThan(Date.now());

    const claimed = claimDeviceLinkCode(db, link.code, { deviceLabel: "Mac mini" });
    expect(claimed.user).toMatchObject({
      handle: "marcus",
      display_name: "Marcus",
      timezone: "America/Los_Angeles",
    });

    const auth = authenticateToken(db, claimed.token.token);
    expect(auth.user.id).toBe(user.id);
    const stored = db
      .prepare("SELECT label FROM auth_tokens WHERE id = ?")
      .get(claimed.token.id);
    expect(stored.label).toBe("Mac mini");
  });

  it("accepts user-typed codes case-insensitively and without the dash", () => {
    const user = createUser(db, { handle: "marcus", displayName: "Marcus" });
    const link = createDeviceLinkCode(db, user.id);
    const sloppy = link.code.toLowerCase().replace("-", " ");
    expect(claimDeviceLinkCode(db, sloppy).user.handle).toBe("marcus");
  });

  it("never stores the raw code", () => {
    const user = createUser(db, { handle: "marcus", displayName: "Marcus" });
    const link = createDeviceLinkCode(db, user.id);
    const row = db.prepare("SELECT code_hash FROM device_link_codes WHERE id = ?").get(link.id);
    expect(row.code_hash).not.toContain(link.code.replace("-", ""));
  });

  it("is single use", () => {
    const user = createUser(db, { handle: "marcus", displayName: "Marcus" });
    const link = createDeviceLinkCode(db, user.id);
    claimDeviceLinkCode(db, link.code);
    expectRelayError(() => claimDeviceLinkCode(db, link.code), "link_code_unusable", 410);
  });

  it("rejects an expired code", () => {
    const user = createUser(db, { handle: "marcus", displayName: "Marcus" });
    const link = createDeviceLinkCode(db, user.id, { ttlMinutes: -1 });
    expectRelayError(() => claimDeviceLinkCode(db, link.code), "link_code_unusable", 410);
  });

  it("purges expired unclaimed codes on the next create, keeping claimed ones", () => {
    const user = createUser(db, { handle: "marcus", displayName: "Marcus" });
    const expired = createDeviceLinkCode(db, user.id, { ttlMinutes: -1 });
    const claimed = createDeviceLinkCode(db, user.id);
    claimDeviceLinkCode(db, claimed.code);

    createDeviceLinkCode(db, user.id);

    const ids = db.prepare("SELECT id FROM device_link_codes").all().map((r) => r.id);
    expect(ids).not.toContain(expired.id);
    expect(ids).toContain(claimed.id);
    expect(ids).toHaveLength(2);
  });

  it("rejects unknown and malformed codes", () => {
    expectRelayError(() => claimDeviceLinkCode(db, "AAAA-AAAA"), "link_code_unusable", 410);
    expectRelayError(() => claimDeviceLinkCode(db, "nope"), "link_code_unusable", 410);
    expectRelayError(() => claimDeviceLinkCode(db, null), "link_code_unusable", 410);
  });

  it("rejects a code for a disabled user", () => {
    const user = createUser(db, { handle: "marcus", displayName: "Marcus" });
    const link = createDeviceLinkCode(db, user.id);
    db.prepare("UPDATE users SET disabled_at = ? WHERE id = ?").run(
      new Date().toISOString(),
      user.id,
    );
    expectRelayError(() => claimDeviceLinkCode(db, link.code), "link_code_unusable", 410);
  });
});

describe("device tokens", () => {
  it("lists active tokens as devices and hides revoked ones", () => {
    const user = createUser(db, { handle: "marcus", displayName: "Marcus" });
    const macbook = createToken(db, user.id, "MacBook");
    const mini = createToken(db, user.id, "Mac mini");

    expect(listTokens(db, user.id).map((d) => d.label)).toEqual(["MacBook", "Mac mini"]);

    revokeToken(db, user.id, mini.id);
    const remaining = listTokens(db, user.id);
    expect(remaining).toHaveLength(1);
    expect(remaining[0]).toMatchObject({ token_id: macbook.id, label: "MacBook" });
  });

  it("does not leak token hashes in the device list", () => {
    const user = createUser(db, { handle: "marcus", displayName: "Marcus" });
    createToken(db, user.id, "MacBook");
    for (const device of listTokens(db, user.id)) {
      expect(Object.keys(device).sort()).toEqual([
        "created_at",
        "label",
        "last_used_at",
        "token_id",
      ]);
    }
  });

  it("mints a fresh labeled token for an existing account", () => {
    const user = createUser(db, { handle: "marcus", displayName: "Marcus", timezone: "UTC" });
    const minted = mintDeviceToken(db, user.id, "Mac mini");

    expect(minted.user).toMatchObject({ handle: "marcus", timezone: "UTC" });
    expect(authenticateToken(db, minted.token.token).user.id).toBe(user.id);
    expect(
      db.prepare("SELECT label FROM auth_tokens WHERE id = ?").get(minted.token.id).label,
    ).toBe("Mac mini");
  });

  it("refuses to mint for a disabled user", () => {
    const user = createUser(db, { handle: "marcus", displayName: "Marcus" });
    db.prepare("UPDATE users SET disabled_at = ? WHERE id = ?").run(
      new Date().toISOString(),
      user.id,
    );
    expectRelayError(() => mintDeviceToken(db, user.id, "Mac mini"), "unauthorized", 401);
  });

  it("scopes the device list and revocation to the caller's account", () => {
    const marcus = createUser(db, { handle: "marcus", displayName: "Marcus" });
    const ken = createUser(db, { handle: "ken", displayName: "Ken" });
    createToken(db, marcus.id, "Marcus MacBook");
    const kensToken = createToken(db, ken.id, "Ken MacBook");

    expect(listTokens(db, marcus.id).map((d) => d.label)).toEqual(["Marcus MacBook"]);

    // Marcus revoking Ken's token id is a silent no-op.
    revokeToken(db, marcus.id, kensToken.id);
    expect(authenticateToken(db, kensToken.token).user.id).toBe(ken.id);
    expect(listTokens(db, ken.id)).toHaveLength(1);
  });
});

describe("statuses and feed", () => {
  // Reference clock a few minutes after the fixtures' updated_at so online rows
  // read as fresh; recency is asserted explicitly in its own test.
  const FEED_NOW = Date.parse("2026-06-06T18:10:00.000Z");

  it("stores an online payload and returns the caller in their feed", () => {
    const user = createUser(db, { handle: "marcus", displayName: "Marcus" });
    const payload = fixture("status-online");

    upsertStatus(db, user, payload);
    const feed = getFeed(db, user, FEED_NOW);

    expect(feed.you.mode).toBe("online");
    expect(feed.you.manual_status).toBe("working on Vibes");
    expect(feed.you.cards.find((card) => card.type === "git_stats").data.commits).toBe(7);
    expect(feed.friends).toHaveLength(0);
    const stored = JSON.parse(db.prepare("SELECT payload_json FROM statuses").get().payload_json);
    expect(stored.day_timezone).toBe("America/Los_Angeles");
    expect(stored.day_start_at).toBe("2026-06-06T07:00:00.000Z");
    expect(stored.day_end_at).toBe("2026-06-07T07:00:00.000Z");
  });

  it("rejects invalid status day-boundary fields", () => {
    const user = createUser(db, { handle: "marcus", displayName: "Marcus" });
    expectRelayError(
      () =>
        upsertStatus(db, user, {
          ...fixture("status-online"),
          day_timezone: "Mars/Base",
        }),
      "invalid_timezone",
      400,
    );
    expectRelayError(
      () =>
        upsertStatus(db, user, {
          ...fixture("status-online"),
          day_start_at: "2026-06-07T07:00:00.000Z",
          day_end_at: "2026-06-06T07:00:00.000Z",
        }),
      "invalid_day_boundary",
      400,
    );
  });

  it("offline preserves the latest shared snapshot", () => {
    const user = createUser(db, { handle: "marcus", displayName: "Marcus" });
    const payload = fixture("status-online");
    upsertStatus(db, user, payload);
    upsertStatus(db, user, {
      ...payload,
      mode: "offline",
      updated_at: "2026-06-06T18:05:00.000Z",
    });

    const feed = getFeed(db, user, FEED_NOW);
    expect(feed.you.mode).toBe("offline");
    expect(feed.you.manual_status).toBe("working on Vibes");
    expect(feed.you.updated_at).toBe("2026-06-06T18:05:00.000Z");
    expect(feed.you.cards.find((card) => card.type === "git_stats").data.commits).toBe(7);
  });

  it("offline without cards preserves the existing device snapshot", () => {
    const user = createUser(db, { handle: "marcus", displayName: "Marcus" });
    const payload = fixture("status-online");
    upsertStatus(db, user, payload);
    upsertStatus(db, user, {
      ...payload,
      mode: "offline",
      day: "2026-06-07",
      manual_status: null,
      cards: [],
      updated_at: "2026-06-06T18:05:00.000Z",
    });

    const feed = getFeed(db, user, FEED_NOW);
    expect(feed.you.mode).toBe("offline");
    expect(feed.you.manual_status).toBeNull();
    expect(feed.you.day).toBe("2026-06-06");
    expect(feed.you.cards.find((card) => card.type === "git_stats").data.commits).toBe(7);
  });

  it("reports a fresh online row as online and a stale one as offline with a last-seen time", () => {
    const user = createUser(db, { handle: "marcus", displayName: "Marcus" });
    const payload = fixture("status-online");
    upsertStatus(db, user, payload);
    const updatedAt = Date.parse(payload.updated_at);

    const fresh = getFeed(db, user, updatedAt + 5 * 60 * 1000);
    expect(fresh.you.mode).toBe("online");
    expect(fresh.you.updated_at).toBe(payload.updated_at);
    expect(fresh.you.cards.length).toBeGreaterThan(0);

    const stale = getFeed(db, user, updatedAt + 30 * 60 * 1000);
    expect(stale.you.mode).toBe("offline");
    expect(stale.you.updated_at).toBe(payload.updated_at);
    expect(stale.you.cards.find((card) => card.type === "git_stats").data.commits).toBe(7);
    expect(stale.you.manual_status).toBe("working on Vibes");
  });

  it("merges multi-device stats for the newest shared client day without exposing legacy agent cards", () => {
    const user = createUser(db, { handle: "marcus", displayName: "Marcus" });
    const payload = fixture("status-online");
    upsertStatus(db, user, payload);
    upsertStatus(db, user, {
      ...payload,
      device_id: "device-marcus-desktop",
      device_label: "Mac mini",
      updated_at: "2026-06-06T18:04:00.000Z",
      cards: [
        {
          type: "git_stats",
          enabled: true,
          summary: "1 repo touched - 2 commits - +10 / -4 LOC",
          data: {
            commits: 2,
            files_changed: 3,
            insertions: 10,
            deletions: 4,
            repos_touched: 1,
          },
        },
        {
          type: "agent_mix",
          enabled: true,
          summary: "Claude Code 100%",
          data: { commit_counts: { claude_code: 2 } },
        },
      ],
    });

    const feed = getFeed(db, user, FEED_NOW);
    const stats = feed.you.cards.find((card) => card.type === "git_stats").data;
    expect(stats.commits).toBe(9);
    expect(stats.insertions).toBe(1258);
    expect(feed.you.cards.find((card) => card.type === "agent_mix")).toBeUndefined();
  });

  it("deduplicates upgraded commit details across devices without exposing fingerprints", () => {
    const user = createUser(db, { handle: "marcus", displayName: "Marcus" });
    const duplicate = "a".repeat(64);
    const unique = "b".repeat(64);
    const base = {
      ...fixture("status-online"),
      cards: [
        {
          type: "git_stats",
          enabled: true,
          summary: null,
          data: {
            commits: 2,
            files_changed: 5,
            insertions: 110,
            deletions: 15,
            repos_touched: 1,
            commit_details: [
              {
                id: duplicate,
                committed_at: "2026-06-06T17:00:00.000Z",
                files_changed: 2,
                insertions: 40,
                deletions: 5,
              },
              {
                id: unique,
                committed_at: "2026-06-06T17:30:00.000Z",
                files_changed: 3,
                insertions: 70,
                deletions: 10,
              },
            ],
          },
        },
      ],
    };
    upsertStatus(db, user, base);
    upsertStatus(db, user, {
      ...base,
      device_id: "device-marcus-desktop",
      updated_at: "2026-06-06T18:04:00.000Z",
      cards: [
        {
          type: "git_stats",
          enabled: true,
          summary: null,
          data: {
            commits: 1,
            files_changed: 2,
            insertions: 40,
            deletions: 5,
            repos_touched: 1,
            commit_details: [
              {
                id: duplicate,
                committed_at: "2026-06-06T17:00:00.000Z",
                files_changed: 2,
                insertions: 40,
                deletions: 5,
              },
            ],
          },
        },
      ],
    });

    const feed = getFeed(db, user, FEED_NOW);
    const stats = feed.you.cards.find((card) => card.type === "git_stats").data;
    expect(stats).toEqual({
      commits: 2,
      files_changed: 5,
      insertions: 110,
      deletions: 15,
      repos_touched: 2,
    });
    expect(JSON.stringify(feed)).not.toContain("commit_details");
    expect(JSON.stringify(feed)).not.toContain(duplicate);
    const rows = db
      .prepare("SELECT commit_id, files_changed, insertions, deletions FROM daily_commits ORDER BY commit_id")
      .all();
    expect(rows).toEqual([
      { commit_id: duplicate, files_changed: 2, insertions: 40, deletions: 5 },
      { commit_id: unique, files_changed: 3, insertions: 70, deletions: 10 },
    ]);
  });

  it("chooses the account timezone's current Vibes day over a newer stale device day", () => {
    const user = createUser(db, {
      handle: "marcus",
      displayName: "Marcus",
      timezone: "America/Los_Angeles",
    });
    const payload = fixture("status-online");
    upsertStatus(db, user, payload);
    upsertStatus(db, user, {
      ...payload,
      device_id: "device-marcus-travel",
      day: "2026-06-05",
      day_timezone: "America/New_York",
      updated_at: "2026-06-06T18:06:00.000Z",
      manual_status: "stale laptop",
      cards: [
        {
          type: "git_stats",
          enabled: true,
          summary: "9 repos touched - 20 commits - +900 / -100 LOC",
          data: {
            commits: 20,
            files_changed: 30,
            insertions: 900,
            deletions: 100,
            repos_touched: 9,
          },
        },
        {
          type: "repo_aliases",
          enabled: true,
          summary: "Travel",
          data: { aliases: ["Travel"] },
        },
      ],
    });

    const feed = getFeed(db, user, FEED_NOW);
    const stats = feed.you.cards.find((card) => card.type === "git_stats").data;
    expect(feed.you.day).toBe("2026-06-06");
    expect(feed.you.manual_status).toBe("working on Vibes");
    expect(stats.commits).toBe(7);
    expect(stats.insertions).toBe(1248);
    expect(feed.you.cards.find((card) => card.type === "repo_aliases").data.aliases).toEqual([
      "Vibes",
      "Braid",
    ]);
    expect(feed.you.updated_at).toBe("2026-06-06T18:06:00.000Z");
  });

  it("persists the newest device timezone once when a legacy account has disagreeing devices", () => {
    const user = createUser(db, { handle: "marcus", displayName: "Marcus" });
    const payload = fixture("status-online");
    upsertStatus(db, user, {
      ...payload,
      device_id: "device-la",
      day_timezone: "America/Los_Angeles",
      updated_at: "2026-06-06T18:02:00.000Z",
    });
    expect(db.prepare("SELECT timezone FROM users WHERE id = ?").get(user.id).timezone).toBeNull();

    upsertStatus(db, user, {
      ...payload,
      device_id: "device-ny",
      day_timezone: "America/New_York",
      updated_at: "2026-06-06T18:04:00.000Z",
    });

    expect(db.prepare("SELECT timezone FROM users WHERE id = ?").get(user.id).timezone).toBe(
      "America/New_York",
    );
  });

  it("does not expose device identifiers or labels in merged feed output", () => {
    const user = createUser(db, { handle: "marcus", displayName: "Marcus" });
    upsertStatus(db, user, fixture("status-online"));

    const json = JSON.stringify(getFeed(db, user, FEED_NOW));
    expect(json).not.toContain("device_id");
    expect(json).not.toContain("device-marcus-macbook");
    expect(json).not.toContain("MacBook");
    expect(json).not.toContain("timezone");
    expect(json).not.toContain("America/Los_Angeles");
  });

  it("uses the newest contributing online row for merged updated_at, ignoring offline rows", () => {
    const user = createUser(db, { handle: "marcus", displayName: "Marcus" });
    const payload = fixture("status-online");
    upsertStatus(db, user, {
      ...payload,
      device_id: "online-device",
      updated_at: "2026-06-06T18:02:00.000Z",
    });
    upsertStatus(db, user, {
      ...payload,
      device_id: "offline-device",
      mode: "offline",
      updated_at: "2026-06-06T19:02:00.000Z",
    });

    const feed = getFeed(db, user, FEED_NOW);
    expect(feed.you.mode).toBe("online");
    expect(feed.you.updated_at).toBe("2026-06-06T18:02:00.000Z");
  });

  it("returns accepted friends and removes them reciprocally", () => {
    const marcus = createUser(db, { handle: "marcus", displayName: "Marcus" });
    const ken = createUser(db, { handle: "ken", displayName: "Ken" });
    const invite = createInvite(db, marcus.id);
    acceptInvite(db, invite.code, { acceptingUserId: ken.id });
    upsertStatus(db, ken, {
      ...fixture("status-online"),
      device_id: "device-ken",
      manual_status: "refactoring",
    });

    expect(getFeed(db, marcus).friends[0].user.handle).toBe("ken");
    removeFriend(db, marcus.id, "ken");
    expect(getFeed(db, marcus).friends).toHaveLength(0);
    expect(getFeed(db, ken).friends).toHaveLength(0);
  });

  it("rejects status payloads over 32 KB", () => {
    const user = createUser(db, { handle: "marcus", displayName: "Marcus" });
    expect(() =>
      upsertStatus(db, user, {
        ...fixture("status-online"),
        cards: [
          {
            type: "git_stats",
            enabled: true,
            summary: "large",
            data: { text: "x".repeat(40_000) },
          },
        ],
      }),
    ).toThrow(RelayError);
  });

  it("rejects oversized disabled cards before filtering them out", () => {
    const user = createUser(db, { handle: "marcus", displayName: "Marcus" });
    expect(() =>
      upsertStatus(db, user, {
        ...fixture("status-online"),
        mode: "offline",
        cards: [
          {
            type: "disabled_blob",
            enabled: false,
            summary: "hidden",
            data: { text: "x".repeat(40_000) },
          },
        ],
      }),
    ).toThrow(RelayError);
  });
});

describe("avatars", () => {
  let avatarDir;
  const savedEnv = {};

  beforeEach(() => {
    for (const key of ["VIBES_AVATAR_STORE", "VIBES_AVATAR_DIR", "VIBES_AVATAR_BASE_URL"]) {
      savedEnv[key] = process.env[key];
    }
    avatarDir = mkdtempSync(join(tmpdir(), "vibes-avatars-"));
    process.env.VIBES_AVATAR_STORE = "filesystem";
    process.env.VIBES_AVATAR_DIR = avatarDir;
    process.env.VIBES_AVATAR_BASE_URL = "https://vibes.test/avatars";
    resetAvatarStore();
  });

  afterEach(() => {
    rmSync(avatarDir, { recursive: true, force: true });
    for (const key of ["VIBES_AVATAR_STORE", "VIBES_AVATAR_DIR", "VIBES_AVATAR_BASE_URL"]) {
      if (savedEnv[key] === undefined) delete process.env[key];
      else process.env[key] = savedEnv[key];
    }
    resetAvatarStore();
  });

  it("newShortId mints unique url-safe slugs", () => {
    const user = createUser(db, { handle: "marcus", displayName: "Marcus" });
    const ids = new Set();
    for (let i = 0; i < 50; i += 1) {
      const id = newShortId(db);
      expect(id).toMatch(/^[-_a-zA-Z0-9]+$/);
      expect(ids.has(id)).toBe(false);
      ids.add(id);
      // Persist the slug so the next call must avoid it (exercises collision check).
      db.prepare(
        `INSERT INTO avatars (id, user_id, store, content_type, width, height, byte_size, created_at)
         VALUES (?, ?, 'filesystem', 'image/png', 1, 1, 1, '2026-01-01T00:00:00.000Z')`,
      ).run(id, user.id);
    }
  });

  it("FilesystemAvatarStore writes <id>.png and builds an immutable URL", () => {
    const store = getAvatarStore();
    expect(store.kind).toBe("filesystem");
    store.put("abc123", fakePng(), "image/png");
    expect(existsSync(join(avatarDir, "abc123.png"))).toBe(true);
    expect(store.urlFor("abc123")).toBe("https://vibes.test/avatars/abc123.png");
    store.remove("abc123");
    expect(existsSync(join(avatarDir, "abc123.png"))).toBe(false);
  });

  it("validatePng accepts a PNG and reads dimensions; rejects non-PNG and oversized", () => {
    expect(validatePng(fakePng(640, 480))).toMatchObject({
      width: 640,
      height: 480,
      byteSize: 33,
    });
    expectRelayError(() => validatePng(Buffer.from("not a png")), "invalid_image", 400);
    expectRelayError(() => validatePng(Buffer.alloc(0)), "invalid_image", 400);
    expectRelayError(() => validatePng(fakePng(2048, 2048)), "invalid_image", 400);
    const huge = fakePng();
    Object.defineProperty(huge, "length", { value: 2_000_000 });
    expectRelayError(() => validatePng(huge), "payload_too_large", 413);
  });

  it("setUserAvatar stores bytes, records a row, and points users.avatar_id", () => {
    const user = createUser(db, { handle: "marcus", displayName: "Marcus" });
    const result = setUserAvatar(db, user, {
      bytes: fakePng(),
      contentType: "image/png",
      width: 512,
      height: 512,
      prompt: "a sleepy fox with headphones",
      style: "illustration",
    });

    expect(result.id).toMatch(/^[-_a-zA-Z0-9]+$/);
    expect(result.avatar_url).toBe(`https://vibes.test/avatars/${result.id}.png`);
    expect(existsSync(join(avatarDir, `${result.id}.png`))).toBe(true);

    const row = db.prepare("SELECT * FROM avatars WHERE id = ?").get(result.id);
    expect(row).toMatchObject({
      user_id: user.id,
      store: "filesystem",
      content_type: "image/png",
      width: 512,
      height: 512,
      byte_size: 33,
      prompt: "a sleepy fox with headphones",
      style: "illustration",
    });
    expect(db.prepare("SELECT avatar_id FROM users WHERE id = ?").get(user.id).avatar_id).toBe(
      result.id,
    );

    expect(avatarUrlFor({ avatar_id: result.id })).toBe(result.avatar_url);
    expect(avatarUrlFor({ avatar_id: null })).toBeNull();
  });

  it("surfaces avatar_url for the viewer and friends in getFeed", () => {
    const marcus = createUser(db, { handle: "marcus", displayName: "Marcus" });
    const ken = createUser(db, { handle: "ken", displayName: "Ken" });
    const invite = createInvite(db, marcus.id);
    acceptInvite(db, invite.code, { acceptingUserId: ken.id });

    const mine = setUserAvatar(db, marcus, {
      bytes: fakePng(),
      contentType: "image/png",
      width: 512,
      height: 512,
    });
    const theirs = setUserAvatar(db, ken, {
      bytes: fakePng(),
      contentType: "image/png",
      width: 512,
      height: 512,
    });

    const feed = getFeed(db, marcus);
    expect(feed.you.user.avatar_url).toBe(mine.avatar_url);
    expect(feed.friends[0].user.avatar_url).toBe(theirs.avatar_url);
  });

  it("HOUSE_STYLE exposes a tunable server-owned template", () => {
    expect(HOUSE_STYLE.styles).toEqual(["illustration", "animation", "sketch"]);
    expect(HOUSE_STYLE.image_size).toBe(512);
    expect(typeof HOUSE_STYLE.prompt_prefix).toBe("string");
    expect(typeof HOUSE_STYLE.prompt_suffix).toBe("string");
  });

  it("validateHexColor accepts #RRGGBB and rejects bad input", () => {
    expect(validateHexColor("#FF6B6B")).toBe("#FF6B6B");
    expect(validateHexColor("  #4d96ff  ")).toBe("#4d96ff");
    for (const bad of ["red", "#xyz", "#fff", "#1234567", "ff6b6b", "", null]) {
      expectRelayError(() => validateHexColor(bad), "invalid_color", 400);
    }
  });

  it("setUserGradient stores both colors and sets avatar_kind='gradient'", () => {
    const user = createUser(db, { handle: "marcus", displayName: "Marcus" });
    const result = setUserGradient(db, user, { start: "#FF6B6B", end: "#4D96FF" });

    expect(result).toEqual({
      avatar_kind: "gradient",
      avatar_gradient: { start: "#FF6B6B", end: "#4D96FF" },
      avatar_url: null,
    });
    const row = db
      .prepare(
        "SELECT avatar_kind, avatar_gradient_start, avatar_gradient_end FROM users WHERE id = ?",
      )
      .get(user.id);
    expect(row).toMatchObject({
      avatar_kind: "gradient",
      avatar_gradient_start: "#FF6B6B",
      avatar_gradient_end: "#4D96FF",
    });
    expect(avatarGradientFor(row)).toEqual({ start: "#FF6B6B", end: "#4D96FF" });
  });

  it("setUserGradient rejects invalid colors before writing", () => {
    const user = createUser(db, { handle: "marcus", displayName: "Marcus" });
    expectRelayError(
      () => setUserGradient(db, user, { start: "red", end: "#4D96FF" }),
      "invalid_color",
      400,
    );
    expectRelayError(
      () => setUserGradient(db, user, { start: "#FF6B6B", end: "#xyz" }),
      "invalid_color",
      400,
    );
    expect(
      db.prepare("SELECT avatar_kind FROM users WHERE id = ?").get(user.id).avatar_kind,
    ).toBeNull();
  });

  it("transitions kind across image -> gradient -> cleared", () => {
    const user = createUser(db, { handle: "marcus", displayName: "Marcus" });

    const image = setUserAvatar(db, user, {
      bytes: fakePng(),
      contentType: "image/png",
      width: 512,
      height: 512,
    });
    let row = db
      .prepare(
        "SELECT avatar_id, avatar_kind, avatar_gradient_start, avatar_gradient_end FROM users WHERE id = ?",
      )
      .get(user.id);
    expect(row.avatar_kind).toBe("image");
    expect(row.avatar_id).toBe(image.id);
    expect(avatarUrlFor(row)).toBe(image.avatar_url);
    expect(avatarGradientFor(row)).toBeNull();

    setUserGradient(db, user, { start: "#FF6B6B", end: "#4D96FF" });
    row = db
      .prepare(
        "SELECT avatar_id, avatar_kind, avatar_gradient_start, avatar_gradient_end FROM users WHERE id = ?",
      )
      .get(user.id);
    expect(row.avatar_kind).toBe("gradient");
    expect(avatarGradientFor(row)).toEqual({ start: "#FF6B6B", end: "#4D96FF" });
    // avatar_id remains but is no longer surfaced as a gradient.
    expect(row.avatar_id).toBe(image.id);
    // The superseded image URL is not emitted once the kind is gradient.
    expect(avatarUrlFor(row)).toBeNull();

    clearUserAvatar(db, user);
    row = db
      .prepare(
        "SELECT avatar_id, avatar_kind, avatar_gradient_start, avatar_gradient_end FROM users WHERE id = ?",
      )
      .get(user.id);
    expect(row).toMatchObject({
      avatar_id: null,
      avatar_kind: null,
      avatar_gradient_start: null,
      avatar_gradient_end: null,
    });
    expect(avatarGradientFor(row)).toBeNull();
    expect(avatarUrlFor(row)).toBeNull();
  });

  it("surfaces avatar_kind + avatar_gradient for the viewer and friends in getFeed", () => {
    const marcus = createUser(db, { handle: "marcus", displayName: "Marcus" });
    const ken = createUser(db, { handle: "ken", displayName: "Ken" });
    const invite = createInvite(db, marcus.id);
    acceptInvite(db, invite.code, { acceptingUserId: ken.id });

    setUserGradient(db, marcus, { start: "#FF6B6B", end: "#4D96FF" });
    const theirs = setUserAvatar(db, ken, {
      bytes: fakePng(),
      contentType: "image/png",
      width: 512,
      height: 512,
    });

    const feed = getFeed(db, marcus);
    expect(feed.you.user.avatar_kind).toBe("gradient");
    expect(feed.you.user.avatar_gradient).toEqual({ start: "#FF6B6B", end: "#4D96FF" });
    expect(feed.you.user.avatar_url).toBeNull();

    expect(feed.friends[0].user.avatar_kind).toBe("image");
    expect(feed.friends[0].user.avatar_gradient).toBeNull();
    expect(feed.friends[0].user.avatar_url).toBe(theirs.avatar_url);
  });
});

describe("contract fixtures", () => {
  it("keeps the shared JSON examples parseable", () => {
    expect(fixture("status-online").mode).toBe("online");
    expect(fixture("feed-response").you.user.handle).toBe("marcus");
    expect(fixture("error").error.code).toBe("unauthorized");
    expect(fixture("avatar-response").avatar_url).toMatch(/\/avatars\/[^/]+\.png$/);
    expect(fixture("feed-response").you.user.avatar_kind).toBeNull();
    expect(fixture("feed-response").you.user.avatar_gradient).toBeNull();
    const gradient = fixture("avatar-gradient-response");
    expect(gradient.avatar_kind).toBe("gradient");
    expect(gradient.avatar_gradient).toMatchObject({
      start: expect.stringMatching(/^#[0-9a-fA-F]{6}$/),
      end: expect.stringMatching(/^#[0-9a-fA-F]{6}$/),
    });
  });
});

describe("http helpers", () => {
  it("rejects raw JSON bodies over the configured byte limit", async () => {
    const request = new Request("https://vibes.test/api/status", {
      method: "POST",
      body: JSON.stringify({ text: "x".repeat(100) }),
      headers: { "content-type": "application/json" },
    });
    await expect(readJson(request, { maxBytes: 32 })).rejects.toThrow(RelayError);
  });

  it("rate limits by nginx-overwritten real IP, not spoofed forwarded-for prefixes", () => {
    const event = {
      request: new Request("https://vibes.test/api/users", {
        headers: {
          "x-real-ip": "203.0.113.10",
          "x-forwarded-for": "198.51.100.99, 203.0.113.10",
        },
      }),
      getClientAddress: () => "127.0.0.1",
    };

    checkRateLimit(event, "test-spoof", 1);
    expect(() => checkRateLimit(event, "test-spoof", 1)).toThrow(RelayError);
  });
});

describe("daily activity and typical churn", () => {
  function postDay(user, day, { commits = 1, insertions, deletions, deviceId = "device-1" }) {
    upsertStatus(db, user, {
      device_id: deviceId,
      mode: "online",
      day,
      updated_at: `${day}T18:00:00.000Z`,
      cards: [
        {
          type: "git_stats",
          enabled: true,
          summary: null,
          data: { commits, insertions, deletions },
        },
      ],
    });
  }

  it("accrues one row per user/device/day, replacing cumulative totals", () => {
    const user = createUser(db, { handle: "marcus", displayName: "Marcus" });
    postDay(user, "2026-06-05", { insertions: 100, deletions: 50 });
    postDay(user, "2026-06-05", { insertions: 200, deletions: 80 });
    postDay(user, "2026-06-06", { insertions: 10, deletions: 0 });

    const rows = db
      .prepare("SELECT client_day, commits, insertions, deletions FROM daily_activity ORDER BY client_day")
      .all();
    expect(rows).toEqual([
      { client_day: "2026-06-05", commits: 1, insertions: 200, deletions: 80 },
      { client_day: "2026-06-06", commits: 1, insertions: 10, deletions: 0 },
    ]);
  });

  it("persists commit counts for history rows", () => {
    const user = createUser(db, { handle: "marcus", displayName: "Marcus" });
    postDay(user, "2026-06-05", { commits: 3, insertions: 0, deletions: 0 });

    const row = db.prepare("SELECT commits, insertions, deletions FROM daily_activity").get();
    expect(row).toEqual({ commits: 3, insertions: 0, deletions: 0 });
  });

  it("computes the median over past active days, excluding the given day", () => {
    const user = createUser(db, { handle: "marcus", displayName: "Marcus" });
    postDay(user, "2026-06-02", { insertions: 80, deletions: 20 }); // churn 100
    postDay(user, "2026-06-03", { insertions: 200, deletions: 100 }); // churn 300
    postDay(user, "2026-06-04", { insertions: 400, deletions: 100 }); // churn 500
    postDay(user, "2026-06-06", { insertions: 9000, deletions: 0 }); // today: excluded

    expect(typicalChurn(db, user.id, "2026-06-06")).toBe(300);
  });

  it("sums devices within a day before taking the median", () => {
    const user = createUser(db, { handle: "marcus", displayName: "Marcus" });
    postDay(user, "2026-06-02", { insertions: 100, deletions: 0 });
    postDay(user, "2026-06-03", { insertions: 100, deletions: 0 });
    postDay(user, "2026-06-04", { insertions: 100, deletions: 0, deviceId: "laptop" });
    postDay(user, "2026-06-04", { insertions: 50, deletions: 25, deviceId: "desktop" });

    // Day churns: 100, 100, 175 → median 100; the multi-device day is one sample.
    expect(typicalChurn(db, user.id, "2026-06-06")).toBe(100);
  });

  it("returns null until three past active days exist", () => {
    const user = createUser(db, { handle: "marcus", displayName: "Marcus" });
    postDay(user, "2026-06-04", { insertions: 100, deletions: 0 });
    postDay(user, "2026-06-05", { insertions: 100, deletions: 0 });
    expect(typicalChurn(db, user.id, "2026-06-06")).toBeNull();
  });

  it("exposes typical_churn in the feed for you and friends", () => {
    const user = createUser(db, { handle: "marcus", displayName: "Marcus" });
    postDay(user, "2026-06-02", { insertions: 100, deletions: 0 });
    postDay(user, "2026-06-03", { insertions: 300, deletions: 0 });
    postDay(user, "2026-06-04", { insertions: 500, deletions: 0 });
    upsertStatus(db, user, fixture("status-online"));

    const feed = getFeed(db, user, Date.parse("2026-06-06T18:10:00.000Z"));
    // History days 100/300/500; the feed day (2026-06-06) is excluded.
    expect(feed.you.typical_churn).toBe(300);

    const friendless = createUser(db, { handle: "new", displayName: "New" });
    expect(getFeed(db, friendless, Date.parse("2026-06-06T18:10:00.000Z")).you.typical_churn).toBeNull();
  });
});
