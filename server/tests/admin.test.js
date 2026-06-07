import { beforeEach, afterEach, describe, expect, it } from "vitest";
import { openDb } from "../src/lib/server/db.js";
import {
  RelayError,
  acceptInvite,
  authenticateToken,
  createInvite,
  createToken,
  createUser,
  upsertStatus,
} from "../src/lib/server/relay.js";
import {
  adminCreateInviteFor,
  adminCreateToken,
  adminRemoveFriendship,
  adminRevokeInvite,
  adminRevokeToken,
  currentlyBroadcasting,
  dashboardStats,
  deleteUser,
  getUserDetail,
  listAllInvites,
  listUsers,
  recordAudit,
  setUserDisabled,
} from "../src/lib/server/admin.js";
import {
  createSession,
  deleteSession,
  isAdminEnabled,
  resolveSession,
  verifyAdminPassword,
} from "../src/lib/server/sessions.js";

/** @type {import('better-sqlite3').Database} */
let db;

beforeEach(() => {
  db = openDb(":memory:");
});

function broadcastPayload(overrides = {}) {
  return {
    device_id: "device-1",
    device_label: "MacBook",
    mode: "broadcasting",
    day: "2026-06-06",
    client_day: "2026-06-06",
    updated_at: "2026-06-06T18:00:00.000Z",
    manual_status: "working",
    derived_status: "vibing",
    cards: [],
    ...overrides,
  };
}

describe("migrations: v2", () => {
  it("creates the sessions and admin_audit tables", () => {
    const tables = db
      .prepare("SELECT name FROM sqlite_master WHERE type = 'table'")
      .all()
      .map((row) => row.name);
    expect(tables).toContain("sessions");
    expect(tables).toContain("admin_audit");
  });
});

describe("listUsers", () => {
  it("returns counts and presence for each user", () => {
    const marcus = createUser(db, { handle: "marcus", displayName: "Marcus" });
    createToken(db, marcus.id, "MacBook");
    const invite = createInvite(db, marcus.id);
    acceptInvite(db, invite.code, { handle: "ken", displayName: "Ken" });
    upsertStatus(db, marcus, broadcastPayload());

    const users = listUsers(db);
    expect(users).toHaveLength(2);
    const row = users.find((u) => u.handle === "marcus");
    expect(row.token_count).toBe(1);
    expect(row.friend_count).toBe(1);
    expect(row.device_count).toBe(1);
    expect(row.presence).toBe("broadcasting");
    expect(row.disabled).toBe(false);
  });

  it("filters by search across handle and display name", () => {
    createUser(db, { handle: "marcus", displayName: "Marcus V" });
    createUser(db, { handle: "ken", displayName: "Kenneth" });
    expect(listUsers(db, { search: "ken" }).map((u) => u.handle)).toEqual(["ken"]);
    expect(listUsers(db, { search: "marc" }).map((u) => u.handle)).toEqual(["marcus"]);
  });

  it("sorts by a whitelisted column and ignores unknown ones", () => {
    createUser(db, { handle: "bravo", displayName: "B" });
    createUser(db, { handle: "alpha", displayName: "A" });
    expect(listUsers(db, { sort: "handle:desc" }).map((u) => u.handle)).toEqual([
      "bravo",
      "alpha",
    ]);
    // Unknown column falls back to handle asc, not an injection.
    expect(
      listUsers(db, { sort: "id; DROP TABLE users" }).map((u) => u.handle),
    ).toEqual(["alpha", "bravo"]);
  });
});

describe("getUserDetail", () => {
  it("returns profile, devices, tokens, invites, friends, and origin", () => {
    const marcus = createUser(db, { handle: "marcus", displayName: "Marcus" });
    const invite = createInvite(db, marcus.id);
    const { user: ken } = acceptInvite(db, invite.code, {
      handle: "ken",
      displayName: "Ken",
    });
    createToken(db, ken.id, "Ken laptop");
    upsertStatus(db, ken, broadcastPayload({ device_id: "ken-1" }));

    const detail = getUserDetail(db, ken.id);
    expect(detail.profile.handle).toBe("ken");
    expect(detail.devices).toHaveLength(1);
    expect(detail.tokens.length).toBeGreaterThanOrEqual(1);
    expect(detail.friends.map((f) => f.handle)).toContain("marcus");
    expect(detail.origin.inviter_handle).toBe("marcus");
    expect(detail.counts.friends).toBe(1);
  });

  it("throws not_found for an unknown id", () => {
    expect(() => getUserDetail(db, "nope")).toThrow(RelayError);
  });

  it("never leaks token or invite secrets", () => {
    const marcus = createUser(db, { handle: "marcus", displayName: "Marcus" });
    createToken(db, marcus.id, "MacBook");
    createInvite(db, marcus.id);
    const json = JSON.stringify(getUserDetail(db, marcus.id));
    expect(json).not.toContain("token_hash");
    expect(json).not.toContain("code_hash");
  });
});

describe("listAllInvites", () => {
  it("includes creator and acceptor handles and derived state", () => {
    const marcus = createUser(db, { handle: "marcus", displayName: "Marcus" });
    const open = createInvite(db, marcus.id);
    const used = createInvite(db, marcus.id);
    acceptInvite(db, used.code, { handle: "ken", displayName: "Ken" });

    const all = listAllInvites(db);
    expect(all).toHaveLength(2);
    const accepted = all.find((i) => i.id === used.id);
    expect(accepted.state).toBe("accepted");
    expect(accepted.creator_handle).toBe("marcus");
    expect(accepted.creator_user_id).toBe(marcus.id);
    expect(accepted.accepted_by).toBe("ken");
    expect(all.find((i) => i.id === open.id).state).toBe("open");
  });

  it("filters by state", () => {
    const marcus = createUser(db, { handle: "marcus", displayName: "Marcus" });
    createInvite(db, marcus.id);
    const used = createInvite(db, marcus.id);
    acceptInvite(db, used.code, { handle: "ken", displayName: "Ken" });
    expect(listAllInvites(db, { state: "open" })).toHaveLength(1);
    expect(listAllInvites(db, { state: "accepted" })).toHaveLength(1);
    expect(listAllInvites(db, { state: "revoked" })).toHaveLength(0);
  });
});

describe("dashboardStats", () => {
  it("tallies users, tokens, invites, and presence", () => {
    const marcus = createUser(db, { handle: "marcus", displayName: "Marcus" });
    createToken(db, marcus.id, "MacBook");
    const invite = createInvite(db, marcus.id);
    acceptInvite(db, invite.code, { handle: "ken", displayName: "Ken" });
    createInvite(db, marcus.id); // an extra open invite
    upsertStatus(db, marcus, broadcastPayload());

    const stats = dashboardStats(db);
    expect(stats.users.total).toBe(2);
    expect(stats.active_tokens).toBeGreaterThanOrEqual(1);
    expect(stats.invites.accepted).toBe(1);
    expect(stats.invites.open).toBe(1);
    expect(stats.presence.broadcasting).toBe(1);
    expect(stats.presence.offline).toBe(1);
  });
});

describe("currentlyBroadcasting", () => {
  it("lists broadcasting users, newest first, skipping disabled", () => {
    const a = createUser(db, { handle: "amy", displayName: "Amy" });
    const b = createUser(db, { handle: "bob", displayName: "Bob" });
    upsertStatus(db, a, broadcastPayload({ updated_at: "2026-06-06T10:00:00.000Z" }));
    upsertStatus(db, b, broadcastPayload({ updated_at: "2026-06-06T12:00:00.000Z" }));
    expect(currentlyBroadcasting(db).map((u) => u.handle)).toEqual(["bob", "amy"]);

    setUserDisabled(db, b.id, true);
    expect(currentlyBroadcasting(db).map((u) => u.handle)).toEqual(["amy"]);
  });
});

describe("setUserDisabled", () => {
  it("disabling blocks token auth without deleting data, enabling restores it", () => {
    const marcus = createUser(db, { handle: "marcus", displayName: "Marcus" });
    const token = createToken(db, marcus.id, "MacBook");
    expect(authenticateToken(db, token.token).user.handle).toBe("marcus");

    setUserDisabled(db, marcus.id, true);
    expect(() => authenticateToken(db, token.token)).toThrow(RelayError);
    // Token row still exists.
    expect(db.prepare("SELECT COUNT(*) AS n FROM auth_tokens").get().n).toBe(1);

    setUserDisabled(db, marcus.id, false);
    expect(authenticateToken(db, token.token).user.handle).toBe("marcus");
  });

  it("throws not_found for an unknown user", () => {
    expect(() => setUserDisabled(db, "nope", true)).toThrow(RelayError);
  });
});

describe("deleteUser", () => {
  it("cascades tokens, friendships, invites, statuses and nulls accepted_by", () => {
    const marcus = createUser(db, { handle: "marcus", displayName: "Marcus" });
    const invite = createInvite(db, marcus.id);
    const { user: ken } = acceptInvite(db, invite.code, {
      handle: "ken",
      displayName: "Ken",
    });
    createToken(db, ken.id, "Ken laptop");
    upsertStatus(db, ken, broadcastPayload({ device_id: "ken-1" }));

    deleteUser(db, ken.id);

    expect(db.prepare("SELECT COUNT(*) AS n FROM users").get().n).toBe(1);
    expect(db.prepare("SELECT COUNT(*) AS n FROM auth_tokens WHERE user_id = ?").get(ken.id).n).toBe(0);
    expect(db.prepare("SELECT COUNT(*) AS n FROM friendships").get().n).toBe(0);
    expect(db.prepare("SELECT COUNT(*) AS n FROM statuses WHERE user_id = ?").get(ken.id).n).toBe(0);
    // Marcus's invite survives, but its accepted_by was nulled (no FK cascade).
    const row = db.prepare("SELECT accepted_by_user_id FROM invites WHERE id = ?").get(invite.id);
    expect(row.accepted_by_user_id).toBeNull();
  });

  it("throws not_found for an unknown user", () => {
    expect(() => deleteUser(db, "nope")).toThrow(RelayError);
  });
});

describe("cross-user invite and token control", () => {
  it("revokes an invite created by anyone", () => {
    const marcus = createUser(db, { handle: "marcus", displayName: "Marcus" });
    const invite = adminCreateInviteFor(db, marcus.id);
    expect(invite.invite_url_path).toMatch(/^\/invite\//);
    adminRevokeInvite(db, invite.id);
    expect(listAllInvites(db, { state: "revoked" }).map((i) => i.id)).toContain(invite.id);
  });

  it("mints and revokes a token for any user", () => {
    const marcus = createUser(db, { handle: "marcus", displayName: "Marcus" });
    const token = adminCreateToken(db, marcus.id, "issued by admin");
    expect(authenticateToken(db, token.token).user.handle).toBe("marcus");
    adminRevokeToken(db, token.id);
    expect(() => authenticateToken(db, token.token)).toThrow(RelayError);
  });

  it("removes a friendship by user ids in both directions", () => {
    const marcus = createUser(db, { handle: "marcus", displayName: "Marcus" });
    const invite = createInvite(db, marcus.id);
    const { user: ken } = acceptInvite(db, invite.code, { handle: "ken", displayName: "Ken" });
    adminRemoveFriendship(db, marcus.id, ken.id);
    expect(db.prepare("SELECT COUNT(*) AS n FROM friendships").get().n).toBe(0);
  });

  it("throws not_found revoking unknown invite or token", () => {
    expect(() => adminRevokeInvite(db, "nope")).toThrow(RelayError);
    expect(() => adminRevokeToken(db, "nope")).toThrow(RelayError);
  });

  it("refuses to revoke an already-accepted invite", () => {
    const marcus = createUser(db, { handle: "marcus", displayName: "Marcus" });
    const invite = createInvite(db, marcus.id);
    acceptInvite(db, invite.code, { handle: "ken", displayName: "Ken" });
    expect(() => adminRevokeInvite(db, invite.id)).toThrow(RelayError);
  });

  it("writes an audit row for each mutation", () => {
    const marcus = createUser(db, { handle: "marcus", displayName: "Marcus" });
    setUserDisabled(db, marcus.id, true);
    const audit = db.prepare("SELECT action FROM admin_audit").all().map((r) => r.action);
    expect(audit).toContain("user.disable");
  });
});

describe("admin sessions", () => {
  const ORIGINAL = process.env.VIBES_ADMIN_PASSWORD;
  afterEach(() => {
    if (ORIGINAL === undefined) delete process.env.VIBES_ADMIN_PASSWORD;
    else process.env.VIBES_ADMIN_PASSWORD = ORIGINAL;
  });

  it("is disabled when no password is configured", () => {
    delete process.env.VIBES_ADMIN_PASSWORD;
    expect(isAdminEnabled()).toBe(false);
    expect(verifyAdminPassword("anything")).toBe(false);
    process.env.VIBES_ADMIN_PASSWORD = "";
    expect(isAdminEnabled()).toBe(false);
  });

  it("verifies the configured password and rejects wrong ones", () => {
    process.env.VIBES_ADMIN_PASSWORD = "correct horse battery staple";
    expect(isAdminEnabled()).toBe(true);
    expect(verifyAdminPassword("correct horse battery staple")).toBe(true);
    expect(verifyAdminPassword("wrong")).toBe(false);
    expect(verifyAdminPassword("")).toBe(false);
  });

  it("issues a session that resolves, then is gone after logout", () => {
    const { token } = createSession(db, { kind: "admin" });
    const session = resolveSession(db, token);
    expect(session.kind).toBe("admin");
    deleteSession(db, token);
    expect(resolveSession(db, token)).toBeNull();
  });

  it("rejects an unknown or empty token", () => {
    expect(resolveSession(db, "made-up")).toBeNull();
    expect(resolveSession(db, "")).toBeNull();
    expect(resolveSession(db, null)).toBeNull();
  });

  it("rejects and deletes an expired session", () => {
    const { token } = createSession(db, { kind: "admin" });
    // Force the row past its absolute expiry.
    db.prepare("UPDATE sessions SET expires_at = ?").run("2000-01-01T00:00:00.000Z");
    expect(resolveSession(db, token)).toBeNull();
    expect(db.prepare("SELECT COUNT(*) AS n FROM sessions").get().n).toBe(0);
  });

  it("rejects a session idle past the idle timeout", () => {
    const { token } = createSession(db, { kind: "admin" });
    db.prepare("UPDATE sessions SET last_seen_at = ?").run("2000-01-01T00:00:00.000Z");
    expect(resolveSession(db, token)).toBeNull();
  });

  it("does not store the raw session token", () => {
    const { token } = createSession(db, { kind: "admin" });
    const stored = db.prepare("SELECT token_hash FROM sessions").get();
    expect(stored.token_hash).not.toContain(token);
  });
});

describe("recordAudit", () => {
  it("appends a row with the given fields", () => {
    recordAudit(db, "test.action", { targetType: "user", targetId: "u1", detail: "x" });
    const row = db.prepare("SELECT * FROM admin_audit").get();
    expect(row.action).toBe("test.action");
    expect(row.target_id).toBe("u1");
  });
});
