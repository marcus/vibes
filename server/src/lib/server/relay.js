import { createHash, randomBytes, randomUUID } from "node:crypto";
import { writeTx } from "./db.js";

const DAY_MS = 24 * 60 * 60 * 1000;

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

/**
 * @param {import('better-sqlite3').Database} db
 * @param {{ handle: string, displayName: string }} input
 */
export function createUser(db, { handle, displayName }) {
  // Handles are stored lowercased so uniqueness is case-insensitive.
  const cleanHandle = String(handle ?? "").trim().toLowerCase();
  const cleanName = String(displayName ?? "").trim();
  if (!cleanHandle) throw new RelayError("invalid_handle", "Handle is required.", 400);
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
 * @param {string} creatorUserId
 * @param {{ ttlDays?: number }} [options]
 */
export function createInvite(db, creatorUserId, { ttlDays = 7 } = {}) {
  const code = newSecret(18);
  const id = randomUUID();
  const expiresAt = new Date(Date.now() + ttlDays * DAY_MS).toISOString();
  // Only the hash is stored. The usable /invite/<code> path is returned once
  // here and never persisted, so a database read cannot recover live codes.
  db.prepare(
    `INSERT INTO invites (id, code_hash, creator_user_id, created_at, expires_at)
     VALUES (?, ?, ?, ?, ?)`,
  ).run(id, sha256(code), creatorUserId, now(), expiresAt);
  return { id, code, invite_url_path: `/invite/${code}`, expires_at: expiresAt };
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
 * Accept an invite: create the accepting user, mint their token, mark the
 * invite used, and create the mutual friendship. All or nothing.
 * @param {import('better-sqlite3').Database} db
 * @param {string} code
 * @param {{ handle: string, displayName: string, deviceLabel?: string|null }} input
 */
export function acceptInvite(db, code, { handle, displayName, deviceLabel = null }) {
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

    const user = createUser(db, { handle, displayName });
    const token = createToken(db, user.id, deviceLabel);

    db.prepare(
      "UPDATE invites SET accepted_by_user_id = ?, accepted_at = ? WHERE id = ?",
    ).run(user.id, now(), invite.id);

    const link = db.prepare(
      `INSERT OR IGNORE INTO friendships (user_id, friend_user_id, state, created_at)
       VALUES (?, ?, 'accepted', ?)`,
    );
    link.run(invite.creator_user_id, user.id, now());
    link.run(user.id, invite.creator_user_id, now());

    return { user, token };
  });
}

/**
 * Look up an invite's creator for display on the accept page. Never exposes the
 * creator's token or any secret.
 * @param {import('better-sqlite3').Database} db
 * @param {string} creatorUserId
 */
export function getUserPublic(db, creatorUserId) {
  return db
    .prepare("SELECT handle, display_name FROM users WHERE id = ?")
    .get(creatorUserId);
}
