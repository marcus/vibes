import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
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
  commitStreak,
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
  networkPulse,
  newShortId,
  registerUser,
  removeFriend,
  resetNetworkPulseCache,
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
  resetNetworkPulseCache();
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

  it("rejects status payloads over the configured status limit", () => {
    const user = createUser(db, { handle: "marcus", displayName: "Marcus" });
    expect(() =>
      upsertStatus(db, user, {
        ...fixture("status-online"),
        cards: [
          {
            type: "git_stats",
            enabled: true,
            summary: "large",
            data: { text: "x".repeat(300_000) },
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
            data: { text: "x".repeat(300_000) },
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
    return upsertStatus(db, user, {
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

  it("stores commit counts per device/day and replaces cumulative totals", () => {
    const user = createUser(db, { handle: "marcus", displayName: "Marcus" });

    vi.useFakeTimers();
    try {
      vi.setSystemTime(new Date("2026-06-05T18:01:00.000Z"));
      postDay(user, "2026-06-05", {
        deviceId: "laptop",
        commits: 2,
        insertions: 11,
        deletions: 3,
      });
      vi.setSystemTime(new Date("2026-06-05T18:02:00.000Z"));
      const replaced = postDay(user, "2026-06-05", {
        deviceId: "laptop",
        commits: 5,
        insertions: 0,
        deletions: 0,
      });
      vi.setSystemTime(new Date("2026-06-05T18:03:00.000Z"));
      const desktop = postDay(user, "2026-06-05", {
        deviceId: "desktop",
        commits: 4,
        insertions: 20,
        deletions: 2,
      });

      const rows = db
        .prepare(
          `SELECT device_id, client_day, commits, insertions, deletions, updated_at
           FROM daily_activity
           ORDER BY device_id`,
        )
        .all();
      expect(rows).toEqual([
        {
          device_id: "desktop",
          client_day: "2026-06-05",
          commits: 4,
          insertions: 20,
          deletions: 2,
          updated_at: desktop.server_received_at,
        },
        {
          device_id: "laptop",
          client_day: "2026-06-05",
          commits: 5,
          insertions: 0,
          deletions: 0,
          updated_at: replaced.server_received_at,
        },
      ]);
    } finally {
      vi.useRealTimers();
    }
  });

  it("computes consecutive commit days through the newest active day", () => {
    const user = createUser(db, { handle: "marcus", displayName: "Marcus" });
    postDay(user, "2026-06-04", { commits: 1, insertions: 20, deletions: 2 });
    postDay(user, "2026-06-05", { commits: 2, insertions: 30, deletions: 3 });
    postDay(user, "2026-06-06", { commits: 1, insertions: 10, deletions: 1 });

    expect(commitStreak(db, user.id, "2026-06-06")).toEqual({
      days: 3,
      through_day: "2026-06-06",
    });
  });

  it("resets the commit streak at gaps", () => {
    const user = createUser(db, { handle: "marcus", displayName: "Marcus" });
    postDay(user, "2026-06-04", { commits: 1, insertions: 20, deletions: 2 });
    postDay(user, "2026-06-06", { commits: 1, insertions: 10, deletions: 1 });

    expect(commitStreak(db, user.id, "2026-06-06")).toEqual({
      days: 1,
      through_day: "2026-06-06",
    });
  });

  it("counts same-day multi-device commits as one streak day", () => {
    const user = createUser(db, { handle: "marcus", displayName: "Marcus" });
    postDay(user, "2026-06-05", { commits: 1, insertions: 20, deletions: 2 });
    postDay(user, "2026-06-06", {
      deviceId: "laptop",
      commits: 2,
      insertions: 30,
      deletions: 3,
    });
    postDay(user, "2026-06-06", {
      deviceId: "desktop",
      commits: 4,
      insertions: 40,
      deletions: 4,
    });

    expect(commitStreak(db, user.id, "2026-06-06")).toEqual({
      days: 2,
      through_day: "2026-06-06",
    });
  });

  it("ignores future commit days when computing the streak", () => {
    const user = createUser(db, { handle: "marcus", displayName: "Marcus" });
    postDay(user, "2026-06-05", { commits: 1, insertions: 20, deletions: 2 });
    postDay(user, "2026-06-06", { commits: 1, insertions: 10, deletions: 1 });
    postDay(user, "2026-06-07", { commits: 1, insertions: 900, deletions: 90 });

    expect(commitStreak(db, user.id, "2026-06-06")).toEqual({
      days: 2,
      through_day: "2026-06-06",
    });
  });

  it("counts zero-churn commit days", () => {
    const user = createUser(db, { handle: "marcus", displayName: "Marcus" });
    postDay(user, "2026-06-05", { commits: 1, insertions: 0, deletions: 0 });
    postDay(user, "2026-06-06", { commits: 1, insertions: 10, deletions: 1 });

    expect(commitStreak(db, user.id, "2026-06-06")).toEqual({
      days: 2,
      through_day: "2026-06-06",
    });
  });

  it("does not count churn-only legacy days as commit streak days", () => {
    const user = createUser(db, { handle: "marcus", displayName: "Marcus" });
    postDay(user, "2026-06-04", { commits: 1, insertions: 20, deletions: 2 });
    postDay(user, "2026-06-05", { commits: 0, insertions: 100, deletions: 10 });
    postDay(user, "2026-06-06", { commits: 1, insertions: 10, deletions: 1 });

    expect(commitStreak(db, user.id, "2026-06-06")).toEqual({
      days: 1,
      through_day: "2026-06-06",
    });
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

  it("exposes commit_streak only when git stats are visible in the feed", () => {
    const user = createUser(db, { handle: "marcus", displayName: "Marcus" });
    postDay(user, "2026-06-04", { commits: 1, insertions: 20, deletions: 2 });
    postDay(user, "2026-06-05", { commits: 1, insertions: 30, deletions: 3 });
    postDay(user, "2026-06-06", { commits: 1, insertions: 10, deletions: 1 });

    const feed = getFeed(db, user, Date.parse("2026-06-06T18:10:00.000Z"));
    expect(feed.you.commit_streak).toEqual({ days: 3, through_day: "2026-06-06" });
    expect(feed.you.cards.find((card) => card.type === "commit_streak")).toBeUndefined();
    expect(JSON.stringify(feed)).not.toContain("daily_activity");
    expect(JSON.stringify(feed)).not.toContain("device-1");

    const hidden = createUser(db, { handle: "hidden", displayName: "Hidden" });
    postDay(hidden, "2026-06-04", { commits: 1, insertions: 20, deletions: 2 });
    postDay(hidden, "2026-06-05", { commits: 1, insertions: 30, deletions: 3 });
    upsertStatus(db, hidden, {
      device_id: "manual-device",
      mode: "online",
      day: "2026-06-06",
      updated_at: "2026-06-06T18:00:00.000Z",
      cards: [
        {
          type: "git_stats",
          enabled: false,
          summary: null,
          data: { commits: 1, insertions: 10, deletions: 1 },
        },
      ],
    });

    const hiddenFeed = getFeed(db, hidden, Date.parse("2026-06-06T18:10:00.000Z"));
    expect(hiddenFeed.you.cards.find((card) => card.type === "git_stats")).toBeUndefined();
    expect(hiddenFeed.you.commit_streak).toBeNull();
  });

  it("anchors feed commit streaks on account timezone and falls back to status day", () => {
    const nowMs = Date.parse("2026-06-06T18:10:00.000Z");
    const insertHistory = db.prepare(
      `INSERT INTO daily_activity (
         user_id, device_id, client_day, commits, insertions, deletions, updated_at
       )
       VALUES (?, ?, ?, 1, 0, 0, ?)`,
    );
    const zoned = createUser(db, {
      handle: "zoned",
      displayName: "Zoned",
      timezone: "America/Los_Angeles",
    });
    postDay(zoned, "2026-06-05", { commits: 1, insertions: 10, deletions: 1 });
    insertHistory.run(zoned.id, "history-device", "2026-06-06", "2026-06-06T18:00:00.000Z");

    const zonedFeed = getFeed(db, zoned, nowMs);
    expect(zonedFeed.you.day).toBe("2026-06-05");
    expect(zonedFeed.you.commit_streak).toEqual({ days: 2, through_day: "2026-06-06" });

    const legacy = createUser(db, { handle: "legacy", displayName: "Legacy" });
    postDay(legacy, "2026-06-05", { commits: 1, insertions: 10, deletions: 1 });
    insertHistory.run(legacy.id, "history-device", "2026-06-06", "2026-06-06T18:00:00.000Z");

    const legacyFeed = getFeed(db, legacy, nowMs);
    expect(legacyFeed.you.day).toBe("2026-06-05");
    expect(legacyFeed.you.commit_streak).toEqual({ days: 1, through_day: "2026-06-05" });
  });
});

describe("network pulse", () => {
  // 2026-06-21 is server-today; the 14-day window spans 2026-06-08..2026-06-21.
  const PULSE_NOW = Date.parse("2026-06-21T18:10:00.000Z");
  const TODAY = "2026-06-21";

  const insertActivity = (db, { userId, day, insertions, deletions, deviceId = "device-1" }) =>
    db
      .prepare(
        `INSERT INTO daily_activity (user_id, device_id, client_day, insertions, deletions, updated_at)
         VALUES (?, ?, ?, ?, ?, ?)`,
      )
      .run(userId, deviceId, day, insertions, deletions, `${day}T18:00:00.000Z`);

  /** Create N distinct users and record activity for each on `day`. */
  function vibe(db, day, count, { insertions = 100, deletions = 50, prefix = day.replace(/-/g, "") } = {}) {
    for (let i = 0; i < count; i += 1) {
      const user = createUser(db, { handle: `${prefix}u${i}`, displayName: `U${i}` });
      insertActivity(db, { userId: user.id, day, insertions, deletions });
    }
  }

  it("aggregates sums and distinct contributors per day across users and devices", () => {
    const a = createUser(db, { handle: "a", displayName: "A" });
    const b = createUser(db, { handle: "b", displayName: "B" });
    const c = createUser(db, { handle: "c", displayName: "C" });
    // a contributes from two devices the same day → still one contributor.
    insertActivity(db, { userId: a.id, day: TODAY, insertions: 100, deletions: 10, deviceId: "laptop" });
    insertActivity(db, { userId: a.id, day: TODAY, insertions: 200, deletions: 20, deviceId: "desktop" });
    insertActivity(db, { userId: b.id, day: TODAY, insertions: 50, deletions: 5 });
    insertActivity(db, { userId: c.id, day: TODAY, insertions: 50, deletions: 5 });

    const pulse = networkPulse(db, PULSE_NOW);
    expect(pulse.window_days).toBe(14);
    expect(pulse.statless).toBe(false);
    expect(pulse.today.contributors).toBe(3);
    expect(pulse.today.insertions).toBe(400);
    expect(pulse.today.deletions).toBe(40);
    expect(pulse.today.churn).toBe(440);
  });

  it("is statless with null today when fewer than three contributors vibe today", () => {
    vibe(db, TODAY, 2);
    const pulse = networkPulse(db, PULSE_NOW);
    expect(pulse.statless).toBe(true);
    expect(pulse.today).toBeNull();
    // History days under the floor are fully suppressed — including the
    // contributor count, which would otherwise leak what the floor hides.
    expect(pulse.history).toHaveLength(1);
    expect(pulse.history[0]).toMatchObject({
      day: TODAY,
      churn: null,
      contributors: null,
      insertions: null,
      deletions: null,
    });
  });

  it("emits today numbers once three distinct contributors vibe", () => {
    vibe(db, TODAY, 3, { insertions: 100, deletions: 50 });
    const pulse = networkPulse(db, PULSE_NOW);
    expect(pulse.statless).toBe(false);
    expect(pulse.today.contributors).toBe(3);
    expect(pulse.today.churn).toBe(450); // 3 × (100 + 50)
  });

  it("suppresses per-day history below the contributor floor but keeps eligible days", () => {
    vibe(db, "2026-06-10", 5, { insertions: 100, deletions: 0, prefix: "d10" }); // churn 500
    vibe(db, "2026-06-11", 2, { insertions: 999, deletions: 1, prefix: "d11" }); // suppressed
    vibe(db, TODAY, 3, { insertions: 100, deletions: 0, prefix: "today" }); // churn 300

    const pulse = networkPulse(db, PULSE_NOW);
    const byDay = Object.fromEntries(pulse.history.map((row) => [row.day, row]));
    expect(byDay["2026-06-10"]).toMatchObject({ churn: 500, insertions: 500, deletions: 0, contributors: 5 });
    expect(byDay["2026-06-11"]).toMatchObject({ churn: null, insertions: null, deletions: null, contributors: null });
    expect(byDay[TODAY]).toMatchObject({ churn: 300, contributors: 3 });
  });

  it("orders history oldest→newest with today last", () => {
    vibe(db, "2026-06-09", 3, { prefix: "d09" });
    vibe(db, "2026-06-15", 3, { prefix: "d15" });
    vibe(db, TODAY, 3, { prefix: "today" });

    const pulse = networkPulse(db, PULSE_NOW);
    expect(pulse.history.map((row) => row.day)).toEqual(["2026-06-09", "2026-06-15", TODAY]);
    expect(pulse.history.at(-1).day).toBe(TODAY);
  });

  it("excludes activity outside the 14-day window", () => {
    vibe(db, "2026-06-07", 3, { prefix: "old" }); // one day before window start
    vibe(db, TODAY, 3, { prefix: "today" });

    const pulse = networkPulse(db, PULSE_NOW);
    expect(pulse.history.map((row) => row.day)).toEqual([TODAY]);
  });

  it("computes lap from churn over the network median, null when not above 1.0", () => {
    // Three eligible history days with churns 300/99/198 → median 198.
    vibe(db, "2026-06-12", 3, { insertions: 100, deletions: 0, prefix: "h12" }); // 300
    vibe(db, "2026-06-13", 3, { insertions: 33, deletions: 0, prefix: "h13" }); // 99 ≈ 100
    vibe(db, "2026-06-14", 3, { insertions: 66, deletions: 0, prefix: "h14" }); // 198 ≈ 200

    // A busy today (churn 600) → typical 198, lap = round(600/198,1) = 3.0.
    vibe(db, TODAY, 3, { insertions: 200, deletions: 0, prefix: "today" });
    const busy = networkPulse(db, PULSE_NOW);
    expect(busy.today.typical_churn).toBe(198);
    expect(busy.today.lap).toBe(3);

    resetNetworkPulseCache();
    db.prepare("DELETE FROM daily_activity WHERE client_day = ?").run(TODAY);
    // A quiet today (churn 99 < typical) → lap null.
    vibe(db, TODAY, 3, { insertions: 33, deletions: 0, prefix: "quiet" });
    const quiet = networkPulse(db, PULSE_NOW);
    expect(quiet.today.lap).toBeNull();
  });

  it("yields null typical_churn until enough eligible network history exists", () => {
    vibe(db, "2026-06-19", 3, { prefix: "h19" });
    vibe(db, "2026-06-20", 3, { prefix: "h20" });
    vibe(db, TODAY, 3, { prefix: "today" });
    const pulse = networkPulse(db, PULSE_NOW);
    expect(pulse.today.typical_churn).toBeNull();
    expect(pulse.today.lap).toBeNull();
  });

  it("caches within the TTL and recomputes after it expires", () => {
    vibe(db, TODAY, 3, { insertions: 100, deletions: 0, prefix: "first" });
    const first = networkPulse(db, PULSE_NOW);
    expect(first.today.contributors).toBe(3);

    // More contributors arrive, but within the 60s TTL the cached value holds.
    vibe(db, TODAY, 2, { insertions: 100, deletions: 0, prefix: "more" });
    const cached = networkPulse(db, PULSE_NOW + 30 * 1000);
    expect(cached.today.contributors).toBe(3);

    // Past the TTL it recomputes.
    const fresh = networkPulse(db, PULSE_NOW + 61 * 1000);
    expect(fresh.today.contributors).toBe(5);
  });

  it("treats a backward clock jump as cache expiry rather than pinning a stale value", () => {
    vibe(db, TODAY, 3, { insertions: 100, deletions: 0, prefix: "first" });
    expect(networkPulse(db, PULSE_NOW).today.contributors).toBe(3);

    // Clock jumps backward (e.g. NTP). The cache age goes negative; without the
    // guard this would stay "fresh" forever. It must recompute instead.
    vibe(db, TODAY, 2, { insertions: 100, deletions: 0, prefix: "more" });
    const rewound = networkPulse(db, PULSE_NOW - 5 * 60 * 1000);
    expect(rewound.today.contributors).toBe(5);
  });

  it("surfaces pulse on the feed and never leaks identity in the serialized form", () => {
    const viewer = createUser(db, { handle: "viewer", displayName: "Viewer" });
    vibe(db, "2026-06-10", 4, { prefix: "h10" });
    vibe(db, TODAY, 3, { prefix: "today" });

    const feed = getFeed(db, viewer, PULSE_NOW);
    expect(feed.pulse).toBeDefined();
    expect(feed.pulse.window_days).toBe(14);

    // Canary: the serialized pulse carries only numeric/null fields and
    // YYYY-MM-DD day strings — no user_id, handle, avatar, or device.
    const allowedTopKeys = new Set(["window_days", "statless", "today", "history"]);
    const allowedTodayKeys = new Set([
      "insertions",
      "deletions",
      "churn",
      "contributors",
      "typical_churn",
      "lap",
    ]);
    const allowedHistoryKeys = new Set([
      "day",
      "churn",
      "contributors",
      "insertions",
      "deletions",
    ]);
    const pulse = JSON.parse(JSON.stringify(feed.pulse));
    expect(new Set(Object.keys(pulse))).toEqual(allowedTopKeys);
    if (pulse.today) {
      Object.keys(pulse.today).forEach((key) => expect(allowedTodayKeys.has(key)).toBe(true));
      Object.values(pulse.today).forEach((value) =>
        expect(value === null || typeof value === "number").toBe(true),
      );
    }
    for (const row of pulse.history) {
      Object.keys(row).forEach((key) => expect(allowedHistoryKeys.has(key)).toBe(true));
      expect(/^\d{4}-\d{2}-\d{2}$/.test(row.day)).toBe(true);
      expect(row.contributors === null || typeof row.contributors === "number").toBe(true);
    }

    const serialized = JSON.stringify(feed.pulse);
    expect(serialized).not.toMatch(/user_id|handle|avatar|device|display_name/);
  });
});
