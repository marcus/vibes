import { beforeEach, describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { migrate, openDb } from "../src/lib/server/db.js";
import {
  RelayError,
  acceptInvite,
  authenticateToken,
  createInvite,
  createToken,
  createUser,
  getFeed,
  getInviteByCode,
  inviteState,
  listInvites,
  removeFriend,
  revokeInvite,
  revokeToken,
  upsertStatus,
} from "../src/lib/server/relay.js";

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

  it("rejects handles that are awkward in invite URLs or setup files", () => {
    expect(() => createUser(db, { handle: "mar cus", displayName: "Marcus" })).toThrow(
      RelayError,
    );
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

describe("statuses and feed", () => {
  it("stores a broadcasting payload and returns the caller in their feed", () => {
    const user = createUser(db, { handle: "marcus", displayName: "Marcus" });
    const payload = fixture("status-broadcasting");

    upsertStatus(db, user, payload);
    const feed = getFeed(db, user);

    expect(feed.you.mode).toBe("broadcasting");
    expect(feed.you.manual_status).toBe("working on Vibes");
    expect(feed.you.cards.find((card) => card.type === "git_stats").data.commits).toBe(7);
    expect(feed.friends).toHaveLength(0);
  });

  it("quiet replaces share cards instead of preserving old broadcast details", () => {
    const user = createUser(db, { handle: "marcus", displayName: "Marcus" });
    const payload = fixture("status-broadcasting");
    upsertStatus(db, user, payload);
    upsertStatus(db, user, {
      ...payload,
      mode: "quiet",
      manual_status: "do not leak",
      derived_status: "quiet",
      updated_at: "2026-06-06T18:05:00.000Z",
    });

    const feed = getFeed(db, user);
    expect(feed.you.mode).toBe("quiet");
    expect(feed.you.manual_status).toBeNull();
    expect(feed.you.cards).toEqual([]);
  });

  it("merges multi-device stats for the newest shared client day", () => {
    const user = createUser(db, { handle: "marcus", displayName: "Marcus" });
    const payload = fixture("status-broadcasting");
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
            uncommitted_insertions: 1,
            uncommitted_deletions: 0,
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

    const feed = getFeed(db, user);
    const stats = feed.you.cards.find((card) => card.type === "git_stats").data;
    const mix = feed.you.cards.find((card) => card.type === "agent_mix").data;
    expect(stats.commits).toBe(9);
    expect(stats.insertions).toBe(1258);
    expect(mix.commit_counts.claude_code).toBe(7);
  });

  it("returns accepted friends and removes them reciprocally", () => {
    const marcus = createUser(db, { handle: "marcus", displayName: "Marcus" });
    const invite = createInvite(db, marcus.id);
    const { user: ken } = acceptInvite(db, invite.code, {
      handle: "ken",
      displayName: "Ken",
    });
    upsertStatus(db, ken, {
      ...fixture("status-broadcasting"),
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
        ...fixture("status-broadcasting"),
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
});

describe("contract fixtures", () => {
  it("keeps the shared JSON examples parseable", () => {
    expect(fixture("status-broadcasting").mode).toBe("broadcasting");
    expect(fixture("feed-response").you.user.handle).toBe("marcus");
    expect(fixture("error").error.code).toBe("unauthorized");
  });
});
