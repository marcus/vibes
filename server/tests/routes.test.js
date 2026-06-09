import { afterAll, beforeEach, describe, expect, it } from "vitest";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const dir = mkdtempSync(join(tmpdir(), "vibes-routes-"));
process.env.VIBES_DB_PATH = join(dir, "routes.sqlite");
process.env.VIBES_AVATAR_STORE = "filesystem";
process.env.VIBES_AVATAR_DIR = join(dir, "avatars");
process.env.VIBES_AVATAR_BASE_URL = "https://vibes.test/avatars";

const [
  { getDb },
  registerRoute,
  meRoute,
  invitesRoute,
  inviteAcceptRoute,
  avatarRoute,
  shortInviteRoute,
  invitePageServer,
  relay,
] = await Promise.all([
  import("../src/lib/server/db.js"),
  import("../src/routes/api/register/+server.js"),
  import("../src/routes/api/me/+server.js"),
  import("../src/routes/api/invites/+server.js"),
  import("../src/routes/api/invites/[code]/accept/+server.js"),
  import("../src/routes/api/avatar/+server.js"),
  import("../src/routes/i/[code]/+server.js"),
  import("../src/routes/invite/[code]/+page.server.js"),
  import("../src/lib/server/relay.js"),
]);

const {
  acceptInvite,
  authenticateToken,
  createInvite,
  createToken,
  createUser,
  registerUser,
  revokeInvite,
} = relay;

const db = getDb();

afterAll(() => {
  try {
    db.close();
  } catch {
    // The process-level shutdown hook also closes this handle in app runtime.
  }
  rmSync(dir, { recursive: true, force: true });
});

beforeEach(() => {
  db.exec(`
    DELETE FROM statuses;
    DELETE FROM friendships;
    DELETE FROM invites;
    DELETE FROM auth_tokens;
    DELETE FROM users;
  `);
});

function routeEvent(path, { body = {}, token = null, params = {}, ip = "203.0.113.20" } = {}) {
  const headers = new Headers({ "content-type": "application/json" });
  if (token) headers.set("authorization", `Bearer ${token}`);
  const request = new Request(`https://vibes.test${path}`, {
    method: "POST",
    headers,
    body: JSON.stringify(body),
  });
  return {
    request,
    params,
    url: new URL(request.url),
    getClientAddress: () => ip,
  };
}

async function responseJson(response) {
  return {
    status: response.status,
    body: await response.json(),
  };
}

describe("POST /api/register", () => {
  it("self-registers a user and returns the raw token once", async () => {
    const response = await registerRoute.POST(
      routeEvent("/api/register", {
        body: { display_name: "Dana Scully", device_label: "Dana MacBook" },
      }),
    );
    const { status, body } = await responseJson(response);

    expect(status).toBe(201);
    expect(body.user).toMatchObject({
      handle: "dana-scully",
      display_name: "Dana Scully",
      timezone: null,
    });
    expect(body.token).toBeTruthy();
    expect(authenticateToken(db, body.token).user.id).toBe(body.user.id);
    expect(
      db.prepare("SELECT label FROM auth_tokens WHERE user_id = ?").get(body.user.id).label,
    ).toBe("Dana MacBook");
  });

  it("stores a registration timezone from the client", async () => {
    const response = await registerRoute.POST(
      routeEvent("/api/register", {
        body: {
          display_name: "Dana Scully",
          device_label: "Dana MacBook",
          timezone: "America/Los_Angeles",
        },
      }),
    );
    const { status, body } = await responseJson(response);

    expect(status).toBe(201);
    expect(body.user.timezone).toBe("America/Los_Angeles");
    expect(db.prepare("SELECT timezone FROM users WHERE id = ?").get(body.user.id).timezone).toBe(
      "America/Los_Angeles",
    );
  });

  it("accepts camelCase aliases and defaults the device label to Mac", async () => {
    const response = await registerRoute.POST(
      routeEvent("/api/register", {
        body: { displayName: "Fox Mulder" },
      }),
    );
    const { status, body } = await responseJson(response);

    expect(status).toBe(201);
    expect(body.user.handle).toBe("fox-mulder");
    expect(db.prepare("SELECT label FROM auth_tokens").get().label).toBe("Mac");
  });

  it("returns a stable validation error for non-object JSON", async () => {
    const response = await registerRoute.POST(
      routeEvent("/api/register", {
        body: null,
      }),
    );

    expect(await responseJson(response)).toMatchObject({
      status: 400,
      body: { error: { code: "invalid_display_name" } },
    });
  });
});

describe("GET /api/me", () => {
  it("returns the authenticated account timezone without using the feed", async () => {
    const { user, token } = registerUser(db, {
      displayName: "Dana Scully",
      deviceLabel: "Dana MacBook",
      timezone: "America/Los_Angeles",
    });
    const request = new Request("https://vibes.test/api/me", {
      method: "GET",
      headers: { authorization: `Bearer ${token.token}` },
    });

    const response = await meRoute.GET({
      request,
      url: new URL(request.url),
      getClientAddress: () => "203.0.113.20",
    });

    expect(await responseJson(response)).toMatchObject({
      status: 200,
      body: {
        user: {
          id: user.id,
          handle: "dana-scully",
          display_name: "Dana Scully",
          timezone: "America/Los_Angeles",
          avatar_url: null,
        },
        house_style: {
          styles: ["illustration", "animation", "sketch"],
          image_size: 512,
        },
      },
    });
  });
});

describe("POST /api/avatar", () => {
  // Build a `type` chunk: [4-byte length][4-byte type][data][4-byte CRC]. The
  // relay's validator/sanitizer does not check CRCs, so a zero placeholder is
  // fine for the fixture.
  function pngChunk(type, data = Buffer.alloc(0)) {
    const out = Buffer.alloc(12 + data.length);
    out.writeUInt32BE(data.length, 0);
    out.write(type, 4, "ascii");
    data.copy(out, 8);
    return out; // trailing 4 CRC bytes left as zero
  }

  // A complete minimal PNG (signature + IHDR + IDAT + IEND). `extraChunks` lets a
  // test append metadata/trailing bytes to verify the sanitizer strips them.
  function fakePng(width = 512, height = 512, extraChunks = []) {
    const ihdr = Buffer.alloc(13);
    ihdr.writeUInt32BE(width, 0);
    ihdr.writeUInt32BE(height, 4);
    ihdr[8] = 8; // bit depth
    ihdr[9] = 6; // color type RGBA
    return Buffer.concat([
      Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
      pngChunk("IHDR", ihdr),
      pngChunk("IDAT", Buffer.from([0x00])),
      ...extraChunks,
      pngChunk("IEND"),
    ]);
  }

  function avatarEvent(body, { token = null, contentType = "image/png", headers = {} } = {}) {
    const h = new Headers({ "content-type": contentType, ...headers });
    if (token) h.set("authorization", `Bearer ${token}`);
    const request = new Request("https://vibes.test/api/avatar", {
      method: "POST",
      headers: h,
      body,
    });
    return { request, url: new URL(request.url), getClientAddress: () => "203.0.113.21" };
  }

  it("stores an uploaded PNG and returns { id, avatar_url }", async () => {
    const { user, token } = registerUser(db, { displayName: "Dana", deviceLabel: "Mac" });
    const response = await avatarRoute.POST(
      avatarEvent(fakePng(), {
        token: token.token,
        headers: { "x-avatar-prompt": "a sleepy fox", "x-avatar-style": "illustration" },
      }),
    );
    const { status, body } = await responseJson(response);

    expect(status).toBe(200);
    expect(body.id).toMatch(/^[-_a-zA-Z0-9]+$/);
    expect(body.avatar_url).toMatch(/\/avatars\/.+\.png$/);
    expect(db.prepare("SELECT avatar_id FROM users WHERE id = ?").get(user.id).avatar_id).toBe(
      body.id,
    );
    const row = db.prepare("SELECT prompt, style FROM avatars WHERE id = ?").get(body.id);
    expect(row).toMatchObject({ prompt: "a sleepy fox", style: "illustration" });
  });

  it("strips metadata chunks and trailing bytes before storing", async () => {
    const { token } = registerUser(db, { displayName: "Dana", deviceLabel: "Mac" });
    const tEXt = pngChunk("tEXt", Buffer.from("Comment secret-metadata"));
    const png = fakePng(512, 512, [tEXt]);
    const appended = Buffer.concat([png, Buffer.from("APPENDED-PAYLOAD")]);
    const response = await avatarRoute.POST(
      avatarEvent(appended, { token: token.token }),
    );
    const { status, body } = await responseJson(response);
    expect(status).toBe(200);
    // Stored byte_size reflects the sanitized PNG, not the appended/metadata bytes.
    const row = db.prepare("SELECT byte_size FROM avatars WHERE id = ?").get(body.id);
    expect(row.byte_size).toBeLessThan(appended.length);
  });

  it("rejects a non-PNG body", async () => {
    const { token } = registerUser(db, { displayName: "Dana", deviceLabel: "Mac" });
    const response = await avatarRoute.POST(
      avatarEvent(Buffer.from("nope"), { token: token.token }),
    );
    expect(await responseJson(response)).toMatchObject({
      status: 400,
      body: { error: { code: "invalid_image" } },
    });
  });

  it("requires authentication", async () => {
    const response = await avatarRoute.POST(avatarEvent(fakePng()));
    expect(await responseJson(response)).toMatchObject({
      status: 401,
      body: { error: { code: "unauthorized" } },
    });
  });

  it("DELETE clears the avatar pointer", async () => {
    const { user, token } = registerUser(db, { displayName: "Dana", deviceLabel: "Mac" });
    await avatarRoute.POST(avatarEvent(fakePng(), { token: token.token }));
    expect(
      db.prepare("SELECT avatar_id FROM users WHERE id = ?").get(user.id).avatar_id,
    ).toBeTruthy();

    const delRequest = new Request("https://vibes.test/api/avatar", {
      method: "DELETE",
      headers: { authorization: `Bearer ${token.token}` },
    });
    const response = await avatarRoute.DELETE({
      request: delRequest,
      url: new URL(delRequest.url),
      getClientAddress: () => "203.0.113.21",
    });
    expect(await responseJson(response)).toMatchObject({ status: 200, body: { ok: true } });
    expect(
      db.prepare("SELECT avatar_id FROM users WHERE id = ?").get(user.id).avatar_id,
    ).toBeNull();
  });
});

describe("POST /api/invites", () => {
  it("creates short app invite URLs under /i", async () => {
    const creator = createUser(db, { handle: "marcus", displayName: "Marcus" });
    const token = createToken(db, creator.id, "MacBook");

    const response = await invitesRoute.POST(
      routeEvent("/api/invites", { token: token.token }),
    );
    const { status, body } = await responseJson(response);

    expect(status).toBe(201);
    expect(body.invite_url).toMatch(/^https:\/\/vibes\.test\/i\/[-_a-zA-Z0-9]+$/);
    expect(body.expires_at).toBeTruthy();
  });
});

describe("GET /i/[code]", () => {
  it("redirects short invite links to the existing invite page", () => {
    try {
      shortInviteRoute.GET({ params: { code: "abc_123-def" } });
      throw new Error("Expected redirect");
    } catch (err) {
      expect(err.status).toBe(307);
      expect(err.location).toBe("/invite/abc_123-def");
    }
  });
});

describe("GET /invite/[code]", () => {
  it("loads open invite hand-off data without creating accounts or tokens", () => {
    const creator = createUser(db, { handle: "marcus", displayName: "Marcus" });
    const invite = createInvite(db, creator.id);

    expect(invitePageServer.load({ params: { code: invite.code } })).toEqual({
      state: "open",
      code: invite.code,
      inviter: "Marcus",
    });
    expect(db.prepare("SELECT count(*) AS n FROM users").get().n).toBe(1);
    expect(db.prepare("SELECT count(*) AS n FROM auth_tokens").get().n).toBe(0);
  });

  it("does not expose the old unauthenticated accept action", () => {
    expect("actions" in invitePageServer).toBe(false);
  });

  it("omits inviter details for unknown or unusable invites", () => {
    expect(invitePageServer.load({ params: { code: "missing" } })).toEqual({
      state: "unusable",
      code: "missing",
      inviter: null,
    });
  });
});

describe("POST /api/invites/[code]/accept", () => {
  it("requires a valid bearer token", async () => {
    const missing = await inviteAcceptRoute.POST(
      routeEvent("/api/invites/nope/accept", { params: { code: "nope" } }),
    );
    expect(await responseJson(missing)).toMatchObject({
      status: 401,
      body: { error: { code: "unauthorized" } },
    });

    const invalid = await inviteAcceptRoute.POST(
      routeEvent("/api/invites/nope/accept", {
        params: { code: "nope" },
        token: "not-a-token",
      }),
    );
    expect(await responseJson(invalid)).toMatchObject({
      status: 401,
      body: { error: { code: "unauthorized" } },
    });
  });

  it.each([
    ["unknown", (creator) => ({ code: "missing-code", user: createUser(db, { handle: "ken", displayName: "Ken" }) })],
    [
      "expired",
      (creator) => ({
        code: createInvite(db, creator.id, { ttlDays: -1 }).code,
        user: createUser(db, { handle: "ken", displayName: "Ken" }),
      }),
    ],
    [
      "revoked",
      (creator) => {
        const invite = createInvite(db, creator.id);
        revokeInvite(db, creator.id, invite.id);
        return {
          code: invite.code,
          user: createUser(db, { handle: "ken", displayName: "Ken" }),
        };
      },
    ],
    [
      "already-used",
      (creator) => {
        const firstFriend = createUser(db, { handle: "ken", displayName: "Ken" });
        const secondFriend = createUser(db, { handle: "sam", displayName: "Sam" });
        const invite = createInvite(db, creator.id);
        acceptInvite(db, invite.code, { acceptingUserId: firstFriend.id });
        return { code: invite.code, user: secondFriend };
      },
    ],
  ])("returns invite_unusable for %s invites", async (_name, setup) => {
    const creator = createUser(db, { handle: "marcus", displayName: "Marcus" });
    const { code, user } = setup(creator);
    const token = createToken(db, user.id, "MacBook");

    const response = await inviteAcceptRoute.POST(
      routeEvent(`/api/invites/${code}/accept`, {
        params: { code },
        token: token.token,
      }),
    );

    expect(await responseJson(response)).toMatchObject({
      status: 410,
      body: { error: { code: "invite_unusable" } },
    });
  });

  it("rejects accepting your own invite", async () => {
    const creator = createUser(db, { handle: "marcus", displayName: "Marcus" });
    const token = createToken(db, creator.id, "MacBook");
    const invite = createInvite(db, creator.id);

    const response = await inviteAcceptRoute.POST(
      routeEvent(`/api/invites/${invite.code}/accept`, {
        params: { code: invite.code },
        token: token.token,
      }),
    );

    expect(await responseJson(response)).toMatchObject({
      status: 400,
      body: { error: { code: "invite_self" } },
    });
  });

  it("links an authenticated user and is idempotent for existing friends", async () => {
    const creator = createUser(db, { handle: "marcus", displayName: "Marcus" });
    const friend = createUser(db, { handle: "ken", displayName: "Ken" });
    const firstInvite = createInvite(db, creator.id);
    acceptInvite(db, firstInvite.code, { acceptingUserId: friend.id });
    const secondInvite = createInvite(db, creator.id);
    const token = createToken(db, friend.id, "MacBook");

    const response = await inviteAcceptRoute.POST(
      routeEvent(`/api/invites/${secondInvite.code}/accept`, {
        params: { code: secondInvite.code },
        token: token.token,
      }),
    );
    const { status, body } = await responseJson(response);

    expect(status).toBe(200);
    expect(body).toEqual({
      inviter: { handle: "marcus", display_name: "Marcus", avatar_url: null },
      friend: { handle: "ken", display_name: "Ken", avatar_url: null },
    });
    expect(db.prepare("SELECT count(*) AS n FROM friendships").get().n).toBe(2);
  });
});
