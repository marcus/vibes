import { randomUUID } from "node:crypto";
import { writeTx } from "./db.js";
import {
  RelayError,
  createInvite,
  createToken,
  inviteState,
  listInvites,
} from "./relay.js";

/**
 * Superuser data layer for the web admin area. This is the only module that
 * reaches across user boundaries — the owner-scoped functions in relay.js stay
 * untouched so they remain safe for a future self-serve `/me`.
 *
 * Reads return plain shapes ready for server-rendered pages. Mutations reuse
 * relay primitives where they exist and drop the owner check, since the
 * superuser has full control. Every mutation records an admin_audit row.
 */

const now = () => new Date().toISOString();

/** Map a presence mode to a comparable rank, matching relay.js MODE_RANK. */
const PRESENCE_CASE =
  "CASE mode WHEN 'broadcasting' THEN 2 WHEN 'quiet' THEN 1 ELSE 0 END";
const RANK_TO_MODE = ["offline", "quiet", "broadcasting"];

/** Whitelisted sort columns for the user list — never interpolate raw input. */
const USER_SORTS = {
  handle: "u.handle",
  display_name: "u.display_name",
  created_at: "u.created_at",
  devices: "device_count",
  tokens: "token_count",
  friends: "friend_count",
  presence: "presence_rank",
};

/**
 * Append an audit row. Best-effort and side-channel only; never throws into a
 * caller's transaction in a way that masks the real mutation result.
 * @param {import('better-sqlite3').Database} db
 * @param {string} action
 * @param {{ targetType?: string|null, targetId?: string|null, detail?: string|null }} [meta]
 */
export function recordAudit(db, action, { targetType = null, targetId = null, detail = null } = {}) {
  db.prepare(
    `INSERT INTO admin_audit (id, action, target_type, target_id, detail, created_at)
     VALUES (?, ?, ?, ?, ?, ?)`,
  ).run(randomUUID(), action, targetType, targetId, detail, now());
}

/* -------------------------------------------------------------------------- */
/* Reads                                                                       */
/* -------------------------------------------------------------------------- */

/**
 * Cross-user listing for the users table. `search` matches handle or display
 * name (case-insensitive); `sort` is `<column>` or `<column>:desc` from the
 * whitelist above.
 * @param {import('better-sqlite3').Database} db
 * @param {{ search?: string, sort?: string }} [options]
 */
export function listUsers(db, { search = "", sort = "handle" } = {}) {
  const [rawColumn, rawDir] = String(sort ?? "").split(":");
  const column = USER_SORTS[rawColumn] ?? USER_SORTS.handle;
  const dir = String(rawDir).toLowerCase() === "desc" ? "DESC" : "ASC";
  // Stable tiebreak on handle so equal counts/presence keep a deterministic order.
  const orderClause =
    column === "u.handle" ? `u.handle ${dir}` : `${column} ${dir}, u.handle ASC`;

  const term = String(search ?? "").trim().toLowerCase();
  const where = term ? "WHERE lower(u.handle) LIKE ? OR lower(u.display_name) LIKE ?" : "";
  const params = term ? [`%${term}%`, `%${term}%`] : [];

  const rows = db
    .prepare(
      `SELECT
         u.id,
         u.handle,
         u.display_name,
         u.created_at,
         u.disabled_at,
         (SELECT COUNT(*) FROM statuses s WHERE s.user_id = u.id) AS device_count,
         (SELECT COUNT(*) FROM auth_tokens t WHERE t.user_id = u.id AND t.revoked_at IS NULL) AS token_count,
         (SELECT COUNT(*) FROM friendships f WHERE f.user_id = u.id AND f.state = 'accepted') AS friend_count,
         (SELECT MAX(${PRESENCE_CASE}) FROM statuses s WHERE s.user_id = u.id) AS presence_rank,
         (SELECT MAX(s.updated_at) FROM statuses s WHERE s.user_id = u.id) AS last_active_at
       FROM users u
       ${where}
       ORDER BY ${orderClause}`,
    )
    .all(...params);

  return rows.map((row) => ({
    id: row.id,
    handle: row.handle,
    display_name: row.display_name,
    created_at: row.created_at,
    disabled_at: row.disabled_at,
    disabled: row.disabled_at != null,
    device_count: row.device_count,
    token_count: row.token_count,
    friend_count: row.friend_count,
    presence: RANK_TO_MODE[row.presence_rank ?? 0],
    last_active_at: row.last_active_at ?? null,
  }));
}

/**
 * Full per-user detail for the manage page: profile, devices/statuses, tokens,
 * invites created, friends, and the invite this user signed up through.
 * @param {import('better-sqlite3').Database} db
 * @param {string} userId
 */
export function getUserDetail(db, userId) {
  const profile = db
    .prepare(
      `SELECT id, handle, display_name, created_at, updated_at, disabled_at
       FROM users WHERE id = ?`,
    )
    .get(userId);
  if (!profile) throw new RelayError("not_found", "User was not found.", 404);

  const devices = db
    .prepare(
      `SELECT device_id, device_label, mode, client_day, updated_at, server_received_at
       FROM statuses
       WHERE user_id = ?
       ORDER BY updated_at DESC`,
    )
    .all(userId)
    .map((row) => ({
      device_id: row.device_id,
      device_label: row.device_label,
      mode: row.mode,
      client_day: row.client_day,
      updated_at: row.updated_at,
      server_received_at: row.server_received_at,
    }));

  const tokens = db
    .prepare(
      `SELECT id, label, created_at, last_used_at, revoked_at
       FROM auth_tokens
       WHERE user_id = ?
       ORDER BY created_at DESC`,
    )
    .all(userId)
    .map((row) => ({
      id: row.id,
      label: row.label,
      created_at: row.created_at,
      last_used_at: row.last_used_at,
      revoked_at: row.revoked_at,
      revoked: row.revoked_at != null,
    }));

  // Reuse the owner-scoped listing — for the creator it is exactly this user's
  // created invites, with derived state and no recoverable code.
  const invites = listInvites(db, userId);

  const friends = db
    .prepare(
      `SELECT friend.id, friend.handle, friend.display_name, f.created_at
       FROM friendships f
       JOIN users friend ON friend.id = f.friend_user_id
       WHERE f.user_id = ? AND f.state = 'accepted'
       ORDER BY friend.handle ASC`,
    )
    .all(userId)
    .map((row) => ({
      id: row.id,
      handle: row.handle,
      display_name: row.display_name,
      since: row.created_at,
    }));

  const origin = db
    .prepare(
      `SELECT inviter.handle AS inviter_handle,
              inviter.display_name AS inviter_display_name,
              i.accepted_at
       FROM invites i
       JOIN users inviter ON inviter.id = i.creator_user_id
       WHERE i.accepted_by_user_id = ?`,
    )
    .get(userId);

  // Strongest presence across the user's devices, for the header badge.
  const presenceRank = devices.reduce(
    (best, d) => Math.max(best, RANK_TO_MODE.indexOf(d.mode)),
    0,
  );

  return {
    profile: {
      id: profile.id,
      handle: profile.handle,
      display_name: profile.display_name,
      created_at: profile.created_at,
      updated_at: profile.updated_at,
      disabled_at: profile.disabled_at,
      disabled: profile.disabled_at != null,
    },
    presence: RANK_TO_MODE[presenceRank],
    devices,
    tokens,
    invites,
    friends,
    origin: origin
      ? {
          inviter_handle: origin.inviter_handle,
          inviter_display_name: origin.inviter_display_name,
          accepted_at: origin.accepted_at,
        }
      : null,
    counts: {
      devices: devices.length,
      tokens_active: tokens.filter((t) => !t.revoked).length,
      tokens_total: tokens.length,
      invites: invites.length,
      friends: friends.length,
    },
  };
}

/**
 * Every invite across the relay with creator and acceptor handles, optionally
 * filtered by derived state.
 * @param {import('better-sqlite3').Database} db
 * @param {{ state?: string }} [options]
 */
export function listAllInvites(db, { state = "all" } = {}) {
  const rows = db
    .prepare(
      `SELECT i.id,
              i.created_at,
              i.accepted_at,
              i.revoked_at,
              i.expires_at,
              i.creator_user_id,
              creator.handle AS creator_handle,
              acceptor.handle AS accepted_by
       FROM invites i
       JOIN users creator ON creator.id = i.creator_user_id
       LEFT JOIN users acceptor ON acceptor.id = i.accepted_by_user_id
       ORDER BY i.created_at DESC`,
    )
    .all()
    .map((row) => ({
      id: row.id,
      state: inviteState(row),
      creator_user_id: row.creator_user_id,
      creator_handle: row.creator_handle,
      accepted_by: row.accepted_by ?? null,
      created_at: row.created_at,
      accepted_at: row.accepted_at,
      expires_at: row.expires_at,
    }));

  const wanted = String(state ?? "all").toLowerCase();
  if (wanted === "all" || !wanted) return rows;
  return rows.filter((invite) => invite.state === wanted);
}

/**
 * Headline counts for the dashboard.
 * @param {import('better-sqlite3').Database} db
 */
export function dashboardStats(db) {
  const userTotals = db
    .prepare(
      `SELECT COUNT(*) AS total,
              SUM(CASE WHEN disabled_at IS NOT NULL THEN 1 ELSE 0 END) AS disabled
       FROM users`,
    )
    .get();

  const activeTokens = db
    .prepare("SELECT COUNT(*) AS n FROM auth_tokens WHERE revoked_at IS NULL")
    .get().n;

  const invites = { open: 0, accepted: 0, expired: 0, revoked: 0, total: 0 };
  for (const invite of listAllInvites(db)) {
    invites[invite.state] = (invites[invite.state] ?? 0) + 1;
    invites.total += 1;
  }

  // Per-user strongest presence, tallied into broadcasting/quiet/offline.
  const presenceRows = db
    .prepare(
      `SELECT u.id,
              (SELECT MAX(${PRESENCE_CASE}) FROM statuses s WHERE s.user_id = u.id) AS rank
       FROM users u`,
    )
    .all();
  const presence = { broadcasting: 0, quiet: 0, offline: 0 };
  for (const row of presenceRows) {
    presence[RANK_TO_MODE[row.rank ?? 0]] += 1;
  }

  return {
    users: { total: userTotals.total ?? 0, disabled: userTotals.disabled ?? 0 },
    active_tokens: activeTokens,
    invites,
    presence,
  };
}

/**
 * Users currently broadcasting, newest activity first, for the dashboard list.
 * @param {import('better-sqlite3').Database} db
 * @param {number} [limit]
 */
export function currentlyBroadcasting(db, limit = 12) {
  return db
    .prepare(
      `SELECT u.id, u.handle, u.display_name, MAX(s.updated_at) AS updated_at
       FROM statuses s
       JOIN users u ON u.id = s.user_id
       WHERE s.mode = 'broadcasting' AND u.disabled_at IS NULL
       GROUP BY u.id
       ORDER BY updated_at DESC
       LIMIT ?`,
    )
    .all(limit)
    .map((row) => ({
      id: row.id,
      handle: row.handle,
      display_name: row.display_name,
      updated_at: row.updated_at,
    }));
}

/**
 * Most recent admin actions, for the dashboard activity strip.
 * @param {import('better-sqlite3').Database} db
 * @param {number} [limit]
 */
export function recentAudit(db, limit = 8) {
  return db
    .prepare(
      `SELECT id, action, target_type, target_id, detail, created_at
       FROM admin_audit
       ORDER BY created_at DESC
       LIMIT ?`,
    )
    .all(limit);
}

/* -------------------------------------------------------------------------- */
/* Mutations (superuser, full control)                                         */
/* -------------------------------------------------------------------------- */

/** Resolve a user row or throw a 404, so mutations fail cleanly on bad ids. */
function requireUser(db, userId) {
  const user = db.prepare("SELECT id, handle FROM users WHERE id = ?").get(userId);
  if (!user) throw new RelayError("not_found", "User was not found.", 404);
  return user;
}

/**
 * Toggle a user's disabled state. A disabled user's tokens immediately fail
 * authenticateToken (it checks users.disabled_at IS NULL) without deleting data.
 * @param {import('better-sqlite3').Database} db
 * @param {string} userId
 * @param {boolean} disabled
 */
export function setUserDisabled(db, userId, disabled) {
  const user = requireUser(db, userId);
  return writeTx(db, () => {
    db.prepare(
      `UPDATE users
       SET disabled_at = ?, updated_at = ?
       WHERE id = ?`,
    ).run(disabled ? now() : null, now(), userId);
    recordAudit(db, disabled ? "user.disable" : "user.enable", {
      targetType: "user",
      targetId: userId,
      detail: user.handle,
    });
    return { ok: true, disabled };
  });
}

/**
 * Hard delete a user. The invites.accepted_by_user_id column has no cascade, so
 * null it out first, then DELETE FROM users cascades tokens, friendships,
 * created invites, and statuses.
 * @param {import('better-sqlite3').Database} db
 * @param {string} userId
 */
export function deleteUser(db, userId) {
  const user = requireUser(db, userId);
  return writeTx(db, () => {
    db.prepare(
      "UPDATE invites SET accepted_by_user_id = NULL WHERE accepted_by_user_id = ?",
    ).run(userId);
    db.prepare("DELETE FROM users WHERE id = ?").run(userId);
    recordAudit(db, "user.delete", {
      targetType: "user",
      targetId: userId,
      detail: user.handle,
    });
    return { ok: true };
  });
}

/**
 * Mint an invite link on behalf of a user. Returns the one-time path/url.
 * @param {import('better-sqlite3').Database} db
 * @param {string} userId
 */
export function adminCreateInviteFor(db, userId) {
  const user = requireUser(db, userId);
  const invite = createInvite(db, userId);
  recordAudit(db, "invite.create", {
    targetType: "invite",
    targetId: invite.id,
    detail: `for ${user.handle}`,
  });
  return invite;
}

/**
 * Revoke any invite regardless of creator (only if still unaccepted).
 * @param {import('better-sqlite3').Database} db
 * @param {string} inviteId
 */
export function adminRevokeInvite(db, inviteId) {
  const existing = db
    .prepare("SELECT id, accepted_at FROM invites WHERE id = ?")
    .get(inviteId);
  if (!existing) throw new RelayError("not_found", "Invite was not found.", 404);
  // An accepted invite cannot be revoked; say so rather than silently no-op.
  if (existing.accepted_at) {
    throw new RelayError("invite_accepted", "An accepted invite cannot be revoked.", 409);
  }
  return writeTx(db, () => {
    db.prepare(
      `UPDATE invites
       SET revoked_at = COALESCE(revoked_at, ?)
       WHERE id = ? AND accepted_at IS NULL`,
    ).run(now(), inviteId);
    recordAudit(db, "invite.revoke", { targetType: "invite", targetId: inviteId });
    return { ok: true };
  });
}

/**
 * Mint a bearer token for any user; the raw token is returned exactly once.
 * @param {import('better-sqlite3').Database} db
 * @param {string} userId
 * @param {string | null} [label]
 */
export function adminCreateToken(db, userId, label = null) {
  const user = requireUser(db, userId);
  const token = createToken(db, userId, label);
  recordAudit(db, "token.create", {
    targetType: "token",
    targetId: token.id,
    detail: `for ${user.handle}`,
  });
  return token;
}

/**
 * Revoke any token by id, regardless of owner.
 * @param {import('better-sqlite3').Database} db
 * @param {string} tokenId
 */
export function adminRevokeToken(db, tokenId) {
  const existing = db.prepare("SELECT id FROM auth_tokens WHERE id = ?").get(tokenId);
  if (!existing) throw new RelayError("not_found", "Token was not found.", 404);
  return writeTx(db, () => {
    db.prepare(
      "UPDATE auth_tokens SET revoked_at = COALESCE(revoked_at, ?) WHERE id = ?",
    ).run(now(), tokenId);
    recordAudit(db, "token.revoke", { targetType: "token", targetId: tokenId });
    return { ok: true };
  });
}

/**
 * Remove a friendship in both directions by user ids.
 * @param {import('better-sqlite3').Database} db
 * @param {string} userId
 * @param {string} friendUserId
 */
export function adminRemoveFriendship(db, userId, friendUserId) {
  return writeTx(db, () => {
    db.prepare(
      `DELETE FROM friendships
       WHERE (user_id = ? AND friend_user_id = ?)
          OR (user_id = ? AND friend_user_id = ?)`,
    ).run(userId, friendUserId, friendUserId, userId);
    recordAudit(db, "friendship.remove", {
      targetType: "user",
      targetId: userId,
      detail: friendUserId,
    });
    return { ok: true };
  });
}
