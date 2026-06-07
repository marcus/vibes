import { createHash, randomBytes, randomUUID, timingSafeEqual } from "node:crypto";

/**
 * Admin session machinery. A single superuser authenticates with the
 * VIBES_ADMIN_PASSWORD env value and receives a DB-backed, cookie-referenced
 * session. Only the SHA-256 hash of the session token is stored, mirroring how
 * bearer tokens and invite codes are handled in relay.js.
 *
 * The `sessions` table carries `kind` ('admin' | 'user') and a nullable
 * `user_id` so a future token-login `/me` page can reuse this same machinery.
 */

const DAY_MS = 24 * 60 * 60 * 1000;
const HOUR_MS = 60 * 60 * 1000;

/** Absolute lifetime: a session is dead this long after it was created. */
const ABSOLUTE_TTL_MS = 7 * DAY_MS;
/** Idle timeout: a session is dead this long after its last activity. */
const IDLE_TTL_MS = 12 * HOUR_MS;

/** Cookie scoped to /admin so it is never sent to the public API or signup pages. */
export const SESSION_COOKIE = "vibes_admin_session";
export const SESSION_COOKIE_PATH = "/admin";

const now = () => new Date().toISOString();
const sha256 = (value) => createHash("sha256").update(value).digest("hex");
const newToken = () => randomBytes(32).toString("base64url");

/** The configured admin password, or "" when the admin area is disabled. */
export function adminPassword() {
  return process.env.VIBES_ADMIN_PASSWORD ?? "";
}

/**
 * The admin area is only mounted when a non-empty password is configured. An
 * un-configured relay returns 404 for every /admin route so it exposes no login
 * surface at all.
 */
export function isAdminEnabled() {
  return adminPassword().length > 0;
}

/**
 * Constant-time password check. Both sides are hashed first so the comparison
 * runs over equal-length digests regardless of the submitted length — this
 * avoids leaking the password length through an early-out on mismatched buffers.
 * @param {string | null | undefined} submitted
 */
export function verifyAdminPassword(submitted) {
  const expected = adminPassword();
  if (!expected) return false;
  const a = Buffer.from(sha256(String(submitted ?? "")), "hex");
  const b = Buffer.from(sha256(expected), "hex");
  return timingSafeEqual(a, b);
}

/**
 * Mint a session row and return the raw token (shown to the cookie only, never
 * stored or logged).
 * @param {import('better-sqlite3').Database} db
 * @param {{ kind?: 'admin' | 'user', userId?: string | null }} [options]
 */
export function createSession(db, { kind = "admin", userId = null } = {}) {
  const token = newToken();
  const id = randomUUID();
  const createdAt = now();
  const expiresAt = new Date(Date.now() + ABSOLUTE_TTL_MS).toISOString();
  db.prepare(
    `INSERT INTO sessions (id, token_hash, kind, user_id, created_at, last_seen_at, expires_at)
     VALUES (?, ?, ?, ?, ?, ?, ?)`,
  ).run(id, sha256(token), kind, userId, createdAt, createdAt, expiresAt);
  return { token, expiresAt };
}

/**
 * Resolve a raw cookie token to a live session, enforcing both absolute expiry
 * and the idle timeout. Expired or idle rows are deleted lazily and treated as
 * absent. On success the row's `last_seen_at` is bumped so activity refreshes
 * the idle window.
 * @param {import('better-sqlite3').Database} db
 * @param {string | null | undefined} rawToken
 * @returns {{ id: string, kind: string, user_id: string | null } | null}
 */
export function resolveSession(db, rawToken) {
  const token = String(rawToken ?? "").trim();
  if (!token) return null;

  const row = db
    .prepare(
      `SELECT id, kind, user_id, last_seen_at, expires_at
       FROM sessions
       WHERE token_hash = ?`,
    )
    .get(sha256(token));
  if (!row) return null;

  const nowMs = Date.now();
  const absoluteDead = Date.parse(row.expires_at) <= nowMs;
  const idleDead =
    row.last_seen_at != null && Date.parse(row.last_seen_at) + IDLE_TTL_MS <= nowMs;
  if (absoluteDead || idleDead) {
    db.prepare("DELETE FROM sessions WHERE id = ?").run(row.id);
    return null;
  }

  db.prepare("UPDATE sessions SET last_seen_at = ? WHERE id = ?").run(now(), row.id);
  return { id: row.id, kind: row.kind, user_id: row.user_id };
}

/**
 * Delete the session row for a raw token (logout). Safe to call with an unknown
 * or empty token.
 * @param {import('better-sqlite3').Database} db
 * @param {string | null | undefined} rawToken
 */
export function deleteSession(db, rawToken) {
  const token = String(rawToken ?? "").trim();
  if (!token) return { ok: true };
  db.prepare("DELETE FROM sessions WHERE token_hash = ?").run(sha256(token));
  return { ok: true };
}

/**
 * Best-effort cleanup of dead rows. Called opportunistically on login so the
 * table does not accumulate expired sessions indefinitely.
 * @param {import('better-sqlite3').Database} db
 */
export function sweepExpiredSessions(db) {
  // Single-statement DELETE: autocommit is atomic and busy_timeout covers
  // cross-process contention, so no writeTx wrapper is needed (see db.js).
  db.prepare(
    `DELETE FROM sessions
     WHERE expires_at <= ?
        OR (last_seen_at IS NOT NULL AND datetime(last_seen_at, '+12 hours') <= datetime('now'))`,
  ).run(now());
}

/**
 * Cookie options for setting the session cookie. `Secure` is enabled whenever
 * the request is served over HTTPS (production behind the proxy); plain-HTTP dev
 * over localhost still works because Secure is omitted there.
 * @param {URL} url
 */
export function sessionCookieOptions(url) {
  return {
    path: SESSION_COOKIE_PATH,
    httpOnly: true,
    sameSite: "lax",
    secure: url.protocol === "https:",
    maxAge: Math.floor(ABSOLUTE_TTL_MS / 1000),
  };
}
