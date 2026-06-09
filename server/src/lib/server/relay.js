import { createHash, randomBytes, randomUUID } from "node:crypto";
import { writeTx } from "./db.js";

const DAY_MS = 24 * 60 * 60 * 1000;
const MAX_HANDLE_LENGTH = 32;
const MAX_STATUS_BYTES = 32 * 1024;
const MODES = new Set(["broadcasting", "quiet", "offline"]);
const MODE_RANK = { offline: 0, quiet: 1, broadcasting: 2 };

/** Error with a stable code and HTTP status for the single error envelope. */
export class RelayError extends Error {
  /**
   * @param {string} code
   * @param {string} message
   * @param {number} status
   */
  constructor(code, message, status) {
    super(message);
    this.name = "RelayError";
    this.code = code;
    this.status = status;
  }
}

const now = () => new Date().toISOString();
const sha256 = (value) => createHash("sha256").update(value).digest("hex");

/** Raw tokens and invite codes are never stored; only their hashes are. */
const newSecret = (bytes) => randomBytes(bytes).toString("base64url");

function publicUser(user) {
  if (!user) return null;
  return { handle: user.handle, display_name: user.display_name };
}

function trimHandleToLength(handle, maxLength = MAX_HANDLE_LENGTH) {
  return handle.slice(0, maxLength).replace(/-+$/g, "") || "friend".slice(0, maxLength);
}

/**
 * Build a URL-safe default handle base from a display name. This is deliberately
 * stricter than admin-created handles: app-first handles use dashes only.
 * @param {string | null | undefined} displayName
 */
export function deriveHandleBase(displayName) {
  const base = String(displayName ?? "")
    .trim()
    .toLowerCase()
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");

  return trimHandleToLength(base || "friend");
}

function handleCandidate(base, attempt) {
  if (attempt === 1) return trimHandleToLength(base);
  const suffix = `-${attempt}`;
  return `${trimHandleToLength(base, MAX_HANDLE_LENGTH - suffix.length)}${suffix}`;
}

/**
 * @param {import('better-sqlite3').Database} db
 * @param {{ handle: string, displayName: string }} input
 */
export function createUser(db, { handle, displayName }) {
  // Handles are stored lowercased so uniqueness is case-insensitive.
  const cleanHandle = String(handle ?? "").trim().toLowerCase();
  const cleanName = String(displayName ?? "").trim();
  if (!cleanHandle) throw new RelayError("invalid_handle", "Handle is required.", 400);
  if (!/^[a-z0-9][a-z0-9_-]*$/.test(cleanHandle)) {
    throw new RelayError(
      "invalid_handle",
      "Use letters, numbers, underscores, or dashes.",
      400,
    );
  }
  if (cleanHandle.length > 32) throw new RelayError("invalid_handle", "Handle is too long.", 400);
  if (!cleanName) throw new RelayError("invalid_display_name", "Display name is required.", 400);
  if (cleanName.length > 64) throw new RelayError("invalid_display_name", "Display name is too long.", 400);

  const id = randomUUID();
  try {
    // Single INSERT — autocommit is atomic. Callers needing multi-step
    // atomicity (e.g. acceptInvite) wrap this in writeTx.
    db.prepare(
      `INSERT INTO users (id, handle, display_name, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?)`,
    ).run(id, cleanHandle, cleanName, now(), now());
  } catch (err) {
    if (String(err).includes("UNIQUE")) {
      throw new RelayError("handle_taken", "That handle is already taken.", 409);
    }
    throw err;
  }
  return { id, handle: cleanHandle, display_name: cleanName };
}

/**
 * Self-register an app user and first device token in one write transaction.
 * @param {import('better-sqlite3').Database} db
 * @param {{ displayName: string, deviceLabel?: string | null, handle?: string | null }} input
 */
export function registerUser(db, { displayName, deviceLabel = null, handle = null }) {
  const handleSource = String(handle ?? "").trim() || displayName;
  const base = deriveHandleBase(handleSource);

  return writeTx(db, () => {
    for (let attempt = 1; attempt <= 1000; attempt += 1) {
      try {
        const user = createUser(db, {
          handle: handleCandidate(base, attempt),
          displayName,
        });
        const token = createToken(db, user.id, deviceLabel);
        return { user, token };
      } catch (err) {
        if (err instanceof RelayError && err.code === "handle_taken") continue;
        throw err;
      }
    }

    throw new RelayError("handle_taken", "Could not find an available handle.", 409);
  });
}

/**
 * Create a bearer token for a user. The raw token is returned exactly once.
 * @param {import('better-sqlite3').Database} db
 * @param {string} userId
 * @param {string | null} [label]
 */
export function createToken(db, userId, label = null) {
  const cleanLabel = label == null ? null : String(label).trim().slice(0, 64) || null;
  const raw = newSecret(32);
  const id = randomUUID();
  db.prepare(
    `INSERT INTO auth_tokens (id, user_id, token_hash, label, created_at)
     VALUES (?, ?, ?, ?, ?)`,
  ).run(id, userId, sha256(raw), cleanLabel, now());
  return { id, token: raw };
}

/**
 * @param {import('better-sqlite3').Database} db
 * @param {string | null | undefined} rawToken
 */
export function authenticateToken(db, rawToken) {
  const token = String(rawToken ?? "").trim();
  if (!token) throw new RelayError("unauthorized", "Authentication is required.", 401);

  const row = db
    .prepare(
      `SELECT
         auth_tokens.id AS token_id,
         auth_tokens.user_id,
         auth_tokens.label,
         users.handle,
         users.display_name
       FROM auth_tokens
       JOIN users ON users.id = auth_tokens.user_id
       WHERE auth_tokens.token_hash = ?
         AND auth_tokens.revoked_at IS NULL
         AND users.disabled_at IS NULL`,
    )
    .get(sha256(token));

  if (!row) throw new RelayError("unauthorized", "Authentication is required.", 401);
  db.prepare("UPDATE auth_tokens SET last_used_at = ? WHERE id = ?").run(now(), row.token_id);
  return {
    token_id: row.token_id,
    user: {
      id: row.user_id,
      handle: row.handle,
      display_name: row.display_name,
    },
  };
}

/**
 * @param {import('better-sqlite3').Database} db
 * @param {string} creatorUserId
 * @param {{ ttlDays?: number }} [options]
 */
export function createInvite(db, creatorUserId, { ttlDays = 7 } = {}) {
  const code = newSecret(18);
  const id = randomUUID();
  const expiresAt = new Date(Date.now() + ttlDays * DAY_MS).toISOString();
  // Only the hash is stored. The usable /i/<code> path is returned once
  // here and never persisted, so a database read cannot recover live codes.
  db.prepare(
    `INSERT INTO invites (id, code_hash, creator_user_id, created_at, expires_at)
     VALUES (?, ?, ?, ?, ?)`,
  ).run(id, sha256(code), creatorUserId, now(), expiresAt);
  return { id, code, invite_url_path: `/i/${code}`, expires_at: expiresAt };
}

/**
 * @param {import('better-sqlite3').Database} db
 * @param {string} creatorUserId
 */
export function listInvites(db, creatorUserId) {
  return db
    .prepare(
      `SELECT invites.id,
              invites.created_at,
              invites.accepted_at,
              invites.revoked_at,
              invites.expires_at,
              users.handle AS accepted_by
       FROM invites
       LEFT JOIN users ON users.id = invites.accepted_by_user_id
       WHERE invites.creator_user_id = ?
       ORDER BY invites.created_at DESC`,
    )
    .all(creatorUserId)
    .map((invite) => ({
      id: invite.id,
      invite_url: null,
      state: inviteState(invite),
      created_at: invite.created_at,
      expires_at: invite.expires_at,
      accepted_by: invite.accepted_by ?? null,
    }));
}

/**
 * @param {import('better-sqlite3').Database} db
 * @param {string} creatorUserId
 * @param {string} inviteId
 */
export function revokeInvite(db, creatorUserId, inviteId) {
  const existing = db
    .prepare("SELECT id FROM invites WHERE id = ? AND creator_user_id = ?")
    .get(inviteId, creatorUserId);
  if (!existing) throw new RelayError("not_found", "Invite was not found.", 404);
  db.prepare(
    `UPDATE invites
     SET revoked_at = COALESCE(revoked_at, ?)
     WHERE id = ? AND accepted_at IS NULL`,
  ).run(now(), inviteId);
  return { ok: true };
}

/**
 * @param {import('better-sqlite3').Database} db
 * @param {string} code
 */
export function getInviteByCode(db, code) {
  return db.prepare("SELECT * FROM invites WHERE code_hash = ?").get(sha256(code));
}

/** @param {{ revoked_at?: string|null, accepted_at?: string|null, expires_at?: string|null }} invite */
export function inviteState(invite) {
  if (invite.revoked_at) return "revoked";
  if (invite.accepted_at) return "accepted";
  if (invite.expires_at && invite.expires_at < now()) return "expired";
  return "open";
}

/**
 * Accept an invite for an existing user: mark the invite used and create the
 * mutual friendship. All or nothing.
 * @param {import('better-sqlite3').Database} db
 * @param {string} code
 * @param {{ acceptingUserId: string }} input
 */
export function acceptInvite(db, code, { acceptingUserId }) {
  // writeTx runs this in an IMMEDIATE transaction, so two concurrent accepts of
  // the same code cannot both read it as open before either writes — this is
  // what keeps the single-use guarantee under concurrency.
  return writeTx(db, () => {
    const invite = getInviteByCode(db, code);
    if (!invite) {
      throw new RelayError("invite_unusable", "This invite is not valid.", 410);
    }
    if (inviteState(invite) !== "open") {
      throw new RelayError(
        "invite_unusable",
        "This invite is expired, revoked, or already used.",
        410,
      );
    }

    const friendId = String(acceptingUserId ?? "").trim();
    if (friendId === invite.creator_user_id) {
      throw new RelayError("invite_self", "You cannot accept your own invite.", 400);
    }

    const inviter = getUserIdentity(db, invite.creator_user_id);
    const friend = getUserIdentity(db, friendId);
    if (!friend) {
      throw new RelayError("not_found", "Accepting user was not found.", 404);
    }
    if (!inviter) {
      throw new RelayError("invite_unusable", "This invite is not valid.", 410);
    }

    const acceptedAt = now();
    db.prepare(
      "UPDATE invites SET accepted_by_user_id = ?, accepted_at = ? WHERE id = ?",
    ).run(friend.id, acceptedAt, invite.id);

    const link = db.prepare(
      `INSERT OR IGNORE INTO friendships (user_id, friend_user_id, state, created_at)
       VALUES (?, ?, 'accepted', ?)`,
    );
    link.run(inviter.id, friend.id, acceptedAt);
    link.run(friend.id, inviter.id, acceptedAt);

    return { inviter: publicUser(inviter), friend: publicUser(friend) };
  });
}

function assertStatusPayloadSize(payload) {
  const bytes = Buffer.byteLength(JSON.stringify(payload), "utf8");
  if (bytes > MAX_STATUS_BYTES) {
    throw new RelayError("payload_too_large", "Status payload is too large.", 413);
  }
}

function sanitizeCard(card) {
  if (!card || typeof card !== "object") return null;
  const type = String(card.type ?? "").trim().slice(0, 64);
  if (!type) return null;
  return {
    type,
    enabled: Boolean(card.enabled),
    summary: card.summary == null ? null : String(card.summary).slice(0, 240),
    data: card.data && typeof card.data === "object" ? card.data : {},
  };
}

function normalizeStatusPayload(authUser, input, receivedAt) {
  assertStatusPayloadSize(input);
  const mode = String(input?.mode ?? "").trim().toLowerCase();
  if (!MODES.has(mode)) throw new RelayError("invalid_mode", "Presence mode is invalid.", 400);

  const clientDay = String(input?.day ?? input?.client_day ?? "").trim();
  if (!/^\d{4}-\d{2}-\d{2}$/.test(clientDay)) {
    throw new RelayError("invalid_client_day", "Client day must be YYYY-MM-DD.", 400);
  }

  const updatedAt = String(input?.updated_at ?? receivedAt).trim();
  if (Number.isNaN(Date.parse(updatedAt))) {
    throw new RelayError("invalid_updated_at", "updated_at must be an ISO timestamp.", 400);
  }

  const cards = Array.isArray(input?.cards)
    ? input.cards.map(sanitizeCard).filter(Boolean).filter((card) => card.enabled)
    : [];
  const sharedCards = mode === "broadcasting" ? cards : [];
  const manualStatus =
    mode === "broadcasting" && input?.manual_status != null
      ? String(input.manual_status).trim().slice(0, 160) || null
      : null;

  const payload = {
    user: {
      handle: authUser.handle,
      display_name: authUser.display_name,
    },
    mode,
    manual_status: manualStatus,
    derived_status:
      mode === "broadcasting"
        ? String(input?.derived_status ?? "vibing").trim().slice(0, 64) || "vibing"
        : mode,
    day: clientDay,
    updated_at: updatedAt,
    cards: sharedCards,
  };
  assertStatusPayloadSize(payload);
  return { payload, mode, clientDay, updatedAt };
}

/**
 * @param {import('better-sqlite3').Database} db
 * @param {{ id: string, handle: string, display_name: string }} user
 * @param {unknown} input
 */
export function upsertStatus(db, user, input) {
  const receivedAt = now();
  const deviceId = String(input?.device_id ?? "").trim();
  if (!deviceId || deviceId.length > 96) {
    throw new RelayError("invalid_device_id", "Device id is required.", 400);
  }
  const deviceLabel = String(input?.device_label ?? "").trim().slice(0, 64) || null;
  const { payload, mode, clientDay, updatedAt } = normalizeStatusPayload(user, input, receivedAt);

  db.prepare(
    `INSERT INTO statuses (
       user_id, device_id, device_label, mode, client_day, payload_json,
       schema_version, updated_at, server_received_at
     )
     VALUES (?, ?, ?, ?, ?, ?, 1, ?, ?)
     ON CONFLICT(user_id, device_id) DO UPDATE SET
       device_label = excluded.device_label,
       mode = excluded.mode,
       client_day = excluded.client_day,
       payload_json = excluded.payload_json,
       schema_version = excluded.schema_version,
       updated_at = excluded.updated_at,
       server_received_at = excluded.server_received_at`,
  ).run(
    user.id,
    deviceId,
    deviceLabel,
    mode,
    clientDay,
    JSON.stringify(payload),
    updatedAt,
    receivedAt,
  );

  return { ok: true, server_received_at: receivedAt };
}

function getCard(payload, type) {
  return payload.cards?.find((card) => card.type === type && card.enabled) ?? null;
}

function sumNumber(total, value) {
  return total + (Number.isFinite(Number(value)) ? Number(value) : 0);
}

function mergeGitStats(rows, latestDay) {
  const stats = {
    commits: 0,
    files_changed: 0,
    insertions: 0,
    deletions: 0,
    uncommitted_insertions: 0,
    uncommitted_deletions: 0,
    repos_touched: 0,
  };
  let found = false;
  for (const row of rows) {
    if (row.mode !== "broadcasting" || row.client_day !== latestDay) continue;
    const card = getCard(row.payload, "git_stats");
    if (!card) continue;
    found = true;
    for (const key of Object.keys(stats)) {
      stats[key] = sumNumber(stats[key], card.data?.[key]);
    }
  }
  if (!found) return null;
  return {
    type: "git_stats",
    enabled: true,
    summary: `${stats.repos_touched} repos touched - ${stats.commits} commits - +${stats.insertions} / -${stats.deletions} LOC`,
    data: stats,
  };
}

function mergeUserStatuses(user, statusRows) {
  if (!statusRows.length) {
    return {
      user,
      mode: "offline",
      manual_status: null,
      derived_status: "offline",
      day: null,
      updated_at: null,
      cards: [],
    };
  }

  const rows = statusRows.map((row) => ({ ...row, payload: JSON.parse(row.payload_json) }));
  const strongest = rows.reduce((best, row) =>
    MODE_RANK[row.mode] > MODE_RANK[best.mode] ? row : best,
  );
  const broadcasting = rows
    .filter((row) => row.mode === "broadcasting")
    .sort((a, b) => Date.parse(b.updated_at) - Date.parse(a.updated_at));
  const source = broadcasting[0] ?? rows.sort((a, b) => Date.parse(b.updated_at) - Date.parse(a.updated_at))[0];
  const latestDay = broadcasting[0]?.client_day ?? source.client_day;
  const contributingRows =
    strongest.mode === "broadcasting"
      ? broadcasting.filter((row) => row.client_day === latestDay)
      : rows.filter((row) => row.mode === strongest.mode);
  const cards = [];
  const gitStats = strongest.mode === "broadcasting" ? mergeGitStats(rows, latestDay) : null;
  if (gitStats) cards.push(gitStats);
  if (strongest.mode === "broadcasting") {
    for (const type of ["repo_aliases", "spotify", "weather"]) {
      const card = getCard(source.payload, type);
      if (card) cards.push(card);
    }
  }

  return {
    user,
    mode: strongest.mode,
    manual_status: strongest.mode === "broadcasting" ? source.payload.manual_status ?? null : null,
    derived_status: strongest.mode === "broadcasting" ? source.payload.derived_status ?? "vibing" : strongest.mode,
    day: latestDay,
    updated_at: contributingRows
      .map((row) => row.updated_at)
      .sort((a, b) => Date.parse(b) - Date.parse(a))[0],
    cards,
  };
}

/**
 * @param {import('better-sqlite3').Database} db
 * @param {{ id: string, handle: string, display_name: string }} viewer
 */
export function getFeed(db, viewer) {
  const users = [
    viewer,
    ...db
      .prepare(
        `SELECT users.id, users.handle, users.display_name
         FROM friendships
         JOIN users ON users.id = friendships.friend_user_id
         WHERE friendships.user_id = ? AND friendships.state = 'accepted'
         ORDER BY users.handle ASC`,
      )
      .all(viewer.id),
  ];

  const statusQuery = db.prepare(
    `SELECT device_id, device_label, mode, client_day, payload_json, updated_at
     FROM statuses
     WHERE user_id = ?
     ORDER BY updated_at DESC`,
  );
  const merged = users.map((user) => mergeUserStatuses(user, statusQuery.all(user.id)));
  return { you: merged[0], friends: merged.slice(1) };
}

/**
 * @param {import('better-sqlite3').Database} db
 * @param {string} userId
 * @param {string} friendHandle
 */
export function removeFriend(db, userId, friendHandle) {
  const handle = String(friendHandle ?? "").trim().toLowerCase();
  return writeTx(db, () => {
    const friend = db.prepare("SELECT id FROM users WHERE handle = ?").get(handle);
    if (!friend) return { ok: true };
    db.prepare(
      `DELETE FROM friendships
       WHERE (user_id = ? AND friend_user_id = ?)
          OR (user_id = ? AND friend_user_id = ?)`,
    ).run(userId, friend.id, friend.id, userId);
    return { ok: true };
  });
}

/**
 * @param {import('better-sqlite3').Database} db
 * @param {string} userId
 * @param {string} tokenId
 */
export function revokeToken(db, userId, tokenId) {
  db.prepare(
    `UPDATE auth_tokens
     SET revoked_at = COALESCE(revoked_at, ?)
     WHERE id = ? AND user_id = ?`,
  ).run(now(), tokenId, userId);
  return { ok: true };
}

/**
 * Look up an invite's creator for display on the accept page. Never exposes the
 * creator's token or any secret.
 * @param {import('better-sqlite3').Database} db
 * @param {string} creatorUserId
 */
export function getUserPublic(db, creatorUserId) {
  return publicUser(getUserIdentity(db, creatorUserId));
}

function getUserIdentity(db, userId) {
  return db
    .prepare("SELECT id, handle, display_name FROM users WHERE id = ?")
    .get(userId);
}
