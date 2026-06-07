import { beforeEach, describe, expect, it } from "vitest";
import { migrate, openDb } from "../src/lib/server/db.js";
import {
  RelayError,
  acceptInvite,
  createInvite,
  createUser,
  getInviteByCode,
  inviteState,
} from "../src/lib/server/relay.js";

/** @type {import('better-sqlite3').Database} */
let db;

beforeEach(() => {
  db = openDb(":memory:");
});

describe("migrations", () => {
  it("creates the v1 tables", () => {
    const tables = db
      .prepare("SELECT name FROM sqlite_master WHERE type = 'table'")
      .all()
      .map((row) => row.name);
    for (const t of ["users", "auth_tokens", "friendships", "invites", "statuses"]) {
      expect(tables).toContain(t);
    }
  });

  it("is idempotent when run again", () => {
    const before = db.prepare("SELECT count(*) AS n FROM schema_migrations").get().n;
    expect(before).toBeGreaterThan(0);
    expect(() => migrate(db)).not.toThrow();
    const after = db.prepare("SELECT count(*) AS n FROM schema_migrations").get().n;
    expect(after).toBe(before);
  });
});

describe("users", () => {
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
});

describe("invites", () => {
  it("accepts an open invite: creates the user, token, and mutual friendship", () => {
    const creator = createUser(db, { handle: "marcus", displayName: "Marcus" });
    const invite = createInvite(db, creator.id);

    const { user, token } = acceptInvite(db, invite.code, {
      handle: "ken",
      displayName: "Ken",
      deviceLabel: "Ken MacBook",
    });

    expect(user.handle).toBe("ken");
    expect(token.token).toBeTruthy();

    const links = db
      .prepare("SELECT user_id, friend_user_id FROM friendships")
      .all();
    expect(links).toHaveLength(2);

    const stored = getInviteByCode(db, invite.code);
    expect(inviteState(stored)).toBe("accepted");
  });

  it("never stores the raw code", () => {
    const creator = createUser(db, { handle: "marcus", displayName: "Marcus" });
    const invite = createInvite(db, creator.id);
    const stored = getInviteByCode(db, invite.code);
    expect(stored.code_hash).not.toContain(invite.code);
  });

  it("rejects a second acceptance of the same invite", () => {
    const creator = createUser(db, { handle: "marcus", displayName: "Marcus" });
    const invite = createInvite(db, creator.id);
    acceptInvite(db, invite.code, { handle: "ken", displayName: "Ken" });
    expect(() =>
      acceptInvite(db, invite.code, { handle: "sam", displayName: "Sam" }),
    ).toThrow(RelayError);
  });

  it("does not create the user when the handle is taken", () => {
    const creator = createUser(db, { handle: "marcus", displayName: "Marcus" });
    createUser(db, { handle: "ken", displayName: "Ken" });
    const invite = createInvite(db, creator.id);

    expect(() =>
      acceptInvite(db, invite.code, { handle: "ken", displayName: "Ken Two" }),
    ).toThrow(RelayError);

    // Invite stays open, no extra users, friendship not created.
    expect(inviteState(getInviteByCode(db, invite.code))).toBe("open");
    expect(db.prepare("SELECT count(*) AS n FROM users").get().n).toBe(2);
    expect(db.prepare("SELECT count(*) AS n FROM friendships").get().n).toBe(0);
  });

  it("reports an unknown code as unusable", () => {
    expect(getInviteByCode(db, "nope")).toBeUndefined();
  });
});
