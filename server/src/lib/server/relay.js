import { createHash, randomBytes, randomInt, randomUUID } from "node:crypto";
import { writeTx } from "./db.js";
import { getAvatarStore } from "./avatarStore.js";

const DAY_MS = 24 * 60 * 60 * 1000;
const MAX_HANDLE_LENGTH = 32;
const MAX_STATUS_BYTES = 32 * 1024;
// Avatar uploads are 512px PNGs; cap raw bytes and dimensions defensively.
const MAX_AVATAR_BYTES = 1_500_000;
const MAX_AVATAR_DIMENSION = 1024;
const MAX_AVATAR_PROMPT_LENGTH = 240;
const MAX_AVATAR_STYLE_LENGTH = 64;

/**
 * Server-owned house-style template for client-side Apple Intelligence
 * generation. Served via /api/me so art direction is tunable without an app
 * release. The client composes prefix + user prompt + suffix and picks the
 * first of `styles` present in the device's available ImagePlayground styles.
 *
 * Wording constraint: ImageCreator's guardrails reject the word "avatar"
 * (it implies a person, and Image Playground blocks people-from-text) with
 * `creationFailed` before generation starts. "icon" passes. Verified
 * empirically 2026-06-12 on macOS 26.
 */
export const HOUSE_STYLE = {
  prompt_prefix: "A friendly minimalist icon of ",
  prompt_suffix: ", centered, simple solid background, soft palette",
  styles: ["illustration", "animation", "sketch"],
  image_size: 512,
};
const MODES = new Set(["online", "offline"]);
const MODE_RANK = { offline: 0, online: 1 };
// typical_churn baseline: median daily churn over this many trailing active
// days (today excluded). Below the minimum the feed publishes null and the
// client falls back to its own cold-start scale.
const TYPICAL_CHURN_WINDOW_DAYS = 14;
const TYPICAL_CHURN_MIN_DAYS = 3;
// Network Pulse: a global, privacy-safe aggregate of the whole network's daily
// churn over a trailing window. Identical for every viewer, so it is computed
// once and cached in-memory keyed on the server-today date string.
const PULSE_WINDOW_DAYS = 14;
// Below this many distinct contributors a day's numbers are suppressed (k-floor)
// so a single person's activity can never be inferred from the aggregate.
const PULSE_MIN_CONTRIBUTORS = 3;
const PULSE_CACHE_TTL_MS = 60 * 1000;
// A friend reports `online` only if they are sharing and have published within
// this window; older online rows fall back to a last-seen "online … ago".
const ONLINE_WINDOW_MS = 10 * 60 * 1000;
const UTC_TIMEZONE = "UTC";
const TIMEZONE_RE = /^[A-Za-z_]+(?:\/[A-Za-z0-9_+-]+){1,3}$/;
const RFC3339_INSTANT_RE = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?Z$/;

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

const HEX_COLOR_RE = /^#[0-9a-fA-F]{6}$/;

/**
 * Validate a `#RRGGBB` hex color, throwing the single error envelope on bad
 * input. Returns the normalized value (trimmed) for storage.
 * @param {unknown} value
 * @param {string} label Field name surfaced in the error message.
 * @returns {string}
 */
export function validateHexColor(value, label = "Color") {
  const text = String(value ?? "").trim();
  if (!HEX_COLOR_RE.test(text)) {
    throw new RelayError("invalid_color", `${label} must be a #RRGGBB hex value.`, 400);
  }
  return text;
}

/**
 * The gradient pair for a user, or null unless `avatar_kind = 'gradient'`. Reads
 * only the row columns so it works for any user/feed/viewer row read.
 * @param {{ avatar_kind?: string | null, avatar_gradient_start?: string | null, avatar_gradient_end?: string | null } | null | undefined} user
 * @returns {{ start: string, end: string } | null}
 */
export function avatarGradientFor(user) {
  if (!user || user.avatar_kind !== "gradient") return null;
  if (!user.avatar_gradient_start || !user.avatar_gradient_end) return null;
  return { start: user.avatar_gradient_start, end: user.avatar_gradient_end };
}

/** Raw tokens and invite codes are never stored; only their hashes are. */
const newSecret = (bytes) => randomBytes(bytes).toString("base64url");

/**
 * Public URL for a user's current avatar image, or null when the current
 * avatar is not an image. `avatar_kind` is the single source of truth: a
 * non-image kind (e.g. `'gradient'`) returns null even when `avatar_id` still
 * points at a superseded image kept as history. The byte store builds the
 * immutable URL from the slug.
 * @param {{ avatar_id?: string | null, avatar_kind?: string | null } | null | undefined} user
 */
export function avatarUrlFor(user) {
  if (user?.avatar_kind && user.avatar_kind !== "image") return null;
  if (!user?.avatar_id) return null;
  return getAvatarStore().urlFor(user.avatar_id);
}

function publicUser(user) {
  if (!user) return null;
  return {
    handle: user.handle,
    display_name: user.display_name,
    avatar_url: avatarUrlFor(user),
    avatar_kind: user.avatar_kind ?? null,
    avatar_gradient: avatarGradientFor(user),
  };
}

function feedUser(user) {
  if (!user) return null;
  return {
    id: user.id,
    handle: user.handle,
    display_name: user.display_name,
    avatar_url: avatarUrlFor(user),
    avatar_kind: user.avatar_kind ?? null,
    avatar_gradient: avatarGradientFor(user),
  };
}

function registeredUser(user) {
  return {
    id: user.id,
    handle: user.handle,
    display_name: user.display_name,
    timezone: user.timezone ?? null,
    avatar_url: avatarUrlFor(user),
    avatar_kind: user.avatar_kind ?? null,
    avatar_gradient: avatarGradientFor(user),
  };
}

function isSupportedTimezone(value) {
  if (value === UTC_TIMEZONE) return true;
  try {
    if (typeof Intl.supportedValuesOf === "function") {
      return Intl.supportedValuesOf("timeZone").includes(value);
    }
  } catch {
    // Fall through to the formatter check below.
  }
  if (!TIMEZONE_RE.test(value)) return false;
  try {
    new Intl.DateTimeFormat("en-US", { timeZone: value }).format(new Date());
    return true;
  } catch {
    return false;
  }
}

function normalizeTimezone(input, { required = false } = {}) {
  const value = String(input ?? "").trim();
  if (!value) {
    if (required) throw new RelayError("invalid_timezone", "Timezone is required.", 400);
    return null;
  }
  if (!isSupportedTimezone(value)) {
    throw new RelayError("invalid_timezone", "Timezone must be a valid IANA identifier.", 400);
  }
  return value;
}

function formatDayInTimezone(timestampMs, timezone) {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: timezone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(new Date(timestampMs));
  const get = (type) => parts.find((part) => part.type === type)?.value;
  return `${get("year")}-${get("month")}-${get("day")}`;
}

function normalizeOptionalInstant(value, key) {
  if (value == null) return null;
  const text = String(value).trim();
  if (!RFC3339_INSTANT_RE.test(text) || Number.isNaN(Date.parse(text))) {
    throw new RelayError("invalid_day_boundary", `${key} must be an ISO timestamp.`, 400);
  }
  return text;
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
 * @param {{ handle: string, displayName: string, timezone?: string | null }} input
 */
export function createUser(db, { handle, displayName, timezone = null }) {
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
  const cleanTimezone = normalizeTimezone(timezone);

  const id = randomUUID();
  try {
    // Single INSERT — autocommit is atomic. Callers needing multi-step
    // atomicity (e.g. acceptInvite) wrap this in writeTx.
    db.prepare(
      `INSERT INTO users (id, handle, display_name, timezone, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?)`,
    ).run(id, cleanHandle, cleanName, cleanTimezone, now(), now());
  } catch (err) {
    if (String(err).includes("UNIQUE")) {
      throw new RelayError("handle_taken", "That handle is already taken.", 409);
    }
    throw err;
  }
  return { id, handle: cleanHandle, display_name: cleanName, timezone: cleanTimezone };
}

/**
 * Self-register an app user and first device token in one write transaction.
 * @param {import('better-sqlite3').Database} db
 * @param {{ displayName: string, deviceLabel?: string | null, handle?: string | null, timezone?: string | null }} input
 */
export function registerUser(db, { displayName, deviceLabel = null, handle = null, timezone = null }) {
  const handleSource = String(handle ?? "").trim() || displayName;
  const base = deriveHandleBase(handleSource);
  const cleanTimezone = normalizeTimezone(timezone);

  return writeTx(db, () => {
    for (let attempt = 1; attempt <= 1000; attempt += 1) {
      try {
        const user = createUser(db, {
          handle: handleCandidate(base, attempt),
          displayName,
          timezone: cleanTimezone,
        });
        const token = createToken(db, user.id, deviceLabel);
        return { user: registeredUser(user), token };
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
         users.display_name,
         users.timezone
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
      timezone: row.timezone,
    },
  };
}

// Device link codes are typed by hand on the new Mac, so they use a short
// human-friendly alphabet (no I/L/O/0/1 lookalikes). 8 chars ≈ 39 bits, which
// with single use, a 10-minute TTL, and the claim rate limit is plenty.
const LINK_CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";
const LINK_CODE_LENGTH = 8;

function newLinkCode() {
  let code = "";
  for (let i = 0; i < LINK_CODE_LENGTH; i += 1) {
    code += LINK_CODE_ALPHABET[randomInt(LINK_CODE_ALPHABET.length)];
  }
  return code;
}

/** Accepts user-typed codes case-insensitively, with or without the dash. */
function normalizeLinkCode(raw) {
  return String(raw ?? "").toUpperCase().replace(/[^A-Z0-9]/g, "");
}

/** "KQ4M7XW2" → "KQ4M-7XW2", purely for display. */
function formatLinkCode(code) {
  return `${code.slice(0, 4)}-${code.slice(4)}`;
}

/**
 * Mint a device link code for adding another Mac to this account. The raw
 * code is returned exactly once; only its hash is stored.
 * @param {import('better-sqlite3').Database} db
 * @param {string} userId
 * @param {{ ttlMinutes?: number }} [options]
 */
export function createDeviceLinkCode(db, userId, { ttlMinutes = 10 } = {}) {
  // Opportunistic cleanup: expired unclaimed codes are dead weight (claimed
  // rows are kept as an audit trail of which devices joined when).
  db.prepare(
    "DELETE FROM device_link_codes WHERE claimed_at IS NULL AND expires_at < ?",
  ).run(now());
  const expiresAt = new Date(Date.now() + ttlMinutes * 60_000).toISOString();
  // The short alphabet makes a hash collision merely unlikely, not
  // negligible, so retry the INSERT a few times on the UNIQUE constraint.
  for (let attempt = 0; attempt < 5; attempt += 1) {
    const code = newLinkCode();
    const id = randomUUID();
    try {
      db.prepare(
        `INSERT INTO device_link_codes (id, code_hash, user_id, created_at, expires_at)
         VALUES (?, ?, ?, ?, ?)`,
      ).run(id, sha256(code), userId, now(), expiresAt);
      return { id, code: formatLinkCode(code), expires_at: expiresAt };
    } catch (err) {
      if (String(err).includes("UNIQUE")) continue;
      throw err;
    }
  }
  throw new RelayError("internal", "Could not allocate a link code.", 500);
}

/**
 * Claim a device link code from a new Mac: mark it used and mint a fresh
 * per-device token. Returns the same shape as registerUser so the client can
 * reuse its registration path. Single use under concurrency for the same
 * reason as acceptInvite (IMMEDIATE transaction).
 * @param {import('better-sqlite3').Database} db
 * @param {string} rawCode
 * @param {{ deviceLabel?: string | null }} [input]
 */
export function claimDeviceLinkCode(db, rawCode, { deviceLabel = null } = {}) {
  const unusable = new RelayError(
    "link_code_unusable",
    "This code is invalid, expired, or already used. Generate a fresh one on your other Mac.",
    410,
  );
  const code = normalizeLinkCode(rawCode);
  if (code.length !== LINK_CODE_LENGTH) throw unusable;

  return writeTx(db, () => {
    const row = db
      .prepare("SELECT * FROM device_link_codes WHERE code_hash = ?")
      .get(sha256(code));
    if (!row || row.claimed_at || row.expires_at < now()) throw unusable;

    const user = db
      .prepare("SELECT * FROM users WHERE id = ? AND disabled_at IS NULL")
      .get(row.user_id);
    if (!user) throw unusable;

    const cleanLabel =
      deviceLabel == null ? null : String(deviceLabel).trim().slice(0, 64) || null;
    db.prepare(
      "UPDATE device_link_codes SET claimed_at = ?, claimed_device_label = ? WHERE id = ?",
    ).run(now(), cleanLabel, row.id);
    const token = createToken(db, user.id, cleanLabel);
    return { user: registeredUser(user), token };
  });
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
  const dayTimezone = normalizeTimezone(input?.day_timezone);
  const dayStartAt = normalizeOptionalInstant(input?.day_start_at, "day_start_at");
  const dayEndAt = normalizeOptionalInstant(input?.day_end_at, "day_end_at");
  if (dayStartAt && dayEndAt && Date.parse(dayStartAt) >= Date.parse(dayEndAt)) {
    throw new RelayError("invalid_day_boundary", "day_start_at must be before day_end_at.", 400);
  }

  const cards = Array.isArray(input?.cards)
    ? input.cards.map(sanitizeCard).filter(Boolean).filter((card) => card.enabled)
    : [];
  const manualStatus =
    input?.manual_status != null
      ? String(input.manual_status).trim().slice(0, 160) || null
      : null;

  const payload = {
    user: {
      handle: authUser.handle,
      display_name: authUser.display_name,
    },
    mode,
    manual_status: manualStatus,
    day: clientDay,
    ...(dayTimezone ? { day_timezone: dayTimezone } : {}),
    ...(dayStartAt ? { day_start_at: dayStartAt } : {}),
    ...(dayEndAt ? { day_end_at: dayEndAt } : {}),
    updated_at: updatedAt,
    cards,
  };
  assertStatusPayloadSize(payload);
  return { payload, mode, clientDay, updatedAt };
}

function newestValidPayloadTimezone(rows) {
  for (const row of rows) {
    try {
      const timezone = JSON.parse(row.payload_json)?.day_timezone;
      if (timezone && isSupportedTimezone(timezone)) return timezone;
    } catch {
      // Ignore malformed historical payloads.
    }
  }
  return null;
}

function maybePersistMissingTimezone(db, userId) {
  const user = db.prepare("SELECT timezone FROM users WHERE id = ?").get(userId);
  if (!user || user.timezone) return;
  const rows = db
    .prepare(
      `SELECT payload_json, updated_at
       FROM statuses
       WHERE user_id = ?
       ORDER BY updated_at DESC`,
    )
    .all(userId);
  const timezones = new Set();
  for (const row of rows) {
    try {
      const timezone = JSON.parse(row.payload_json)?.day_timezone;
      if (timezone && isSupportedTimezone(timezone)) timezones.add(timezone);
    } catch {
      // Ignore malformed historical payloads.
    }
  }
  if (timezones.size < 2) return;
  const chosen = newestValidPayloadTimezone(rows);
  if (!chosen) return;
  db.prepare("UPDATE users SET timezone = ?, updated_at = ? WHERE id = ? AND timezone IS NULL").run(
    chosen,
    now(),
    userId,
  );
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
  let { payload, mode, clientDay, updatedAt } = normalizeStatusPayload(user, input, receivedAt);
  if (mode === "offline" && payload.cards.length === 0) {
    const previous = db
      .prepare(
        `SELECT client_day, payload_json
         FROM statuses
         WHERE user_id = ? AND device_id = ?`,
      )
      .get(user.id, deviceId);
    if (previous) {
      const previousPayload = JSON.parse(previous.payload_json);
      if (Array.isArray(previousPayload.cards) && previousPayload.cards.length > 0) {
        payload = {
          ...payload,
          day: previousPayload.day ?? previous.client_day ?? payload.day,
          ...(previousPayload.day_timezone ? { day_timezone: previousPayload.day_timezone } : {}),
          ...(previousPayload.day_start_at ? { day_start_at: previousPayload.day_start_at } : {}),
          ...(previousPayload.day_end_at ? { day_end_at: previousPayload.day_end_at } : {}),
          cards: previousPayload.cards,
        };
        clientDay = previous.client_day ?? previousPayload.day ?? clientDay;
        assertStatusPayloadSize(payload);
      }
    }
  }

  writeTx(db, () => {
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
    recordDailyActivity(db, user.id, deviceId, payload, receivedAt);
    maybePersistMissingTimezone(db, user.id);
  });

  return { ok: true, server_received_at: receivedAt };
}

/**
 * Accrue the day's git churn into daily_activity. The scanner reports
 * cumulative day totals, so the upsert replaces (not adds). Days without a
 * git_stats card leave no row — the typical-churn median only considers days
 * the user actually shared activity for.
 */
function recordDailyActivity(db, userId, deviceId, payload, receivedAt) {
  const card = getCard(payload, "git_stats");
  if (!card) return;
  const commits = Math.max(0, Number(card.data?.commits) || 0);
  const insertions = Math.max(0, Number(card.data?.insertions) || 0);
  const deletions = Math.max(0, Number(card.data?.deletions) || 0);
  db.prepare(
    `INSERT INTO daily_activity (user_id, device_id, client_day, commits, insertions, deletions, updated_at)
     VALUES (?, ?, ?, ?, ?, ?, ?)
     ON CONFLICT(user_id, device_id, client_day) DO UPDATE SET
       commits = excluded.commits,
       insertions = excluded.insertions,
       deletions = excluded.deletions,
       updated_at = excluded.updated_at`,
  ).run(userId, deviceId, payload.day, commits, insertions, deletions, receivedAt);
  recordDailyCommits(db, userId, payload.day, card, receivedAt);
}

/**
 * Median daily churn (insertions + deletions, summed across devices) over the
 * most recent TYPICAL_CHURN_WINDOW_DAYS active days, excluding `excludeDay`
 * (the in-progress day, which would bias the baseline downward intraday).
 * Returns null until TYPICAL_CHURN_MIN_DAYS of history exist.
 * @param {import('better-sqlite3').Database} db
 * @param {string} userId
 * @param {string | null} excludeDay
 * @returns {number | null}
 */
export function typicalChurn(db, userId, excludeDay) {
  const rows = db
    .prepare(
      `SELECT SUM(insertions + deletions) AS churn
       FROM daily_activity
       WHERE user_id = ? AND client_day <> ?
       GROUP BY client_day
       HAVING churn > 0
       ORDER BY client_day DESC
       LIMIT ?`,
    )
    .all(userId, excludeDay ?? "", TYPICAL_CHURN_WINDOW_DAYS);
  if (rows.length < TYPICAL_CHURN_MIN_DAYS) return null;
  const sorted = rows.map((row) => row.churn).sort((a, b) => a - b);
  const mid = Math.floor(sorted.length / 2);
  return sorted.length % 2 ? sorted[mid] : Math.round((sorted[mid - 1] + sorted[mid]) / 2);
}

function previousDay(day) {
  const timestamp = Date.parse(`${day}T00:00:00.000Z`);
  if (Number.isNaN(timestamp)) return null;
  return new Date(timestamp - DAY_MS).toISOString().slice(0, 10);
}

/** In-memory cache for the network pulse, keyed on the server-today UTC date. */
let pulseCache = null;

/** Drop the cached network pulse — for tests that reseed the DB within a day. */
export function resetNetworkPulseCache() {
  pulseCache = null;
}

/**
 * Median network churn across all contributing days in the window — the
 * "typical day" baseline the today ring is measured against. Mirrors
 * {@link typicalChurn} but global (all users, not one) and over already-summed
 * per-day churns. Returns null until PULSE_MIN_CONTRIBUTORS-eligible history
 * exists. Today is excluded so an in-progress day cannot drag the baseline down.
 * @param {Array<{ day: string, churn: number, contributors: number }>} days
 *   Per-day aggregates oldest→newest, today last.
 * @param {string} today
 * @returns {number | null}
 */
function networkTypicalChurn(days, today) {
  const churns = days
    .filter(
      (row) =>
        row.day !== today && row.contributors >= PULSE_MIN_CONTRIBUTORS && row.churn > 0,
    )
    .map((row) => row.churn);
  if (churns.length < TYPICAL_CHURN_MIN_DAYS) return null;
  const sorted = churns.sort((a, b) => a - b);
  const mid = Math.floor(sorted.length / 2);
  return sorted.length % 2 ? sorted[mid] : Math.round((sorted[mid - 1] + sorted[mid]) / 2);
}

/**
 * Aggregate, privacy-safe "sign of life" for the whole network over the trailing
 * PULSE_WINDOW_DAYS calendar days up to and including server-today (UTC). Source
 * is the per-(user,device,day) `daily_activity` table; everything here is sums,
 * distinct-user counts, and date strings — never identity.
 *
 * Today's headline numbers only emit when today has >= PULSE_MIN_CONTRIBUTORS
 * distinct contributors; otherwise `statless` is true and `today` is null (the
 * client shows "people are vibing today" with no numbers). In `history`, any day
 * below the floor has its churn/insertions/deletions suppressed to null.
 *
 * The whole object is identical for every viewer, so it is cached in-memory with
 * a ~60s TTL keyed on the server-today date string; it recomputes when the date
 * rolls over or the TTL expires.
 * @param {import('better-sqlite3').Database} db
 * @param {number} [nowMs] Reference clock, injectable for tests.
 * @returns {{ window_days: number, statless: boolean, today: object | null, history: Array<object> }}
 */
export function networkPulse(db, nowMs = Date.now()) {
  const today = new Date(nowMs).toISOString().slice(0, 10);
  // A backward wall-clock jump (e.g. NTP correction) makes the age negative; treat
  // that as expired so a stale entry can't be pinned alive indefinitely.
  const cacheAge = pulseCache ? nowMs - pulseCache.computedAt : Infinity;
  if (pulseCache && pulseCache.today === today && cacheAge >= 0 && cacheAge < PULSE_CACHE_TTL_MS) {
    return pulseCache.pulse;
  }

  const windowStart = new Date(Date.parse(`${today}T00:00:00.000Z`) - (PULSE_WINDOW_DAYS - 1) * DAY_MS)
    .toISOString()
    .slice(0, 10);
  const rows = db
    .prepare(
      `SELECT client_day AS day,
              SUM(insertions) AS insertions,
              SUM(deletions) AS deletions,
              COUNT(DISTINCT user_id) AS contributors
       FROM daily_activity
       WHERE client_day >= ? AND client_day <= ?
       GROUP BY client_day
       ORDER BY client_day ASC`,
    )
    .all(windowStart, today)
    .map((row) => ({
      day: row.day,
      insertions: row.insertions,
      deletions: row.deletions,
      churn: row.insertions + row.deletions,
      contributors: row.contributors,
    }));

  const typicalChurnValue = networkTypicalChurn(rows, today);
  const history = rows.map((row) =>
    row.contributors >= PULSE_MIN_CONTRIBUTORS
      ? {
          day: row.day,
          churn: row.churn,
          contributors: row.contributors,
          insertions: row.insertions,
          deletions: row.deletions,
        }
      : {
          // Below the floor, even the contributor count is withheld — emitting
          // it would leak exactly what the k-floor exists to hide (e.g. "1").
          day: row.day,
          churn: null,
          contributors: null,
          insertions: null,
          deletions: null,
        },
  );

  const todayRow = rows.find((row) => row.day === today) ?? null;
  const statless = !todayRow || todayRow.contributors < PULSE_MIN_CONTRIBUTORS;
  const todayPulse = statless
    ? null
    : {
        insertions: todayRow.insertions,
        deletions: todayRow.deletions,
        churn: todayRow.churn,
        contributors: todayRow.contributors,
        typical_churn: typicalChurnValue,
        lap:
          typicalChurnValue && todayRow.churn / typicalChurnValue > 1
            ? Math.round((todayRow.churn / typicalChurnValue) * 10) / 10
            : null,
      };

  const pulse = {
    window_days: PULSE_WINDOW_DAYS,
    statless,
    today: todayPulse,
    history,
  };
  pulseCache = { today, computedAt: nowMs, pulse };
  return pulse;
}

/**
 * Current commit streak, summed across devices and capped at the user's current
 * Vibes day. Returns only the aggregate summary safe for feed responses.
 * @param {import('better-sqlite3').Database} db
 * @param {string} userId
 * @param {string | null} currentDay
 * @returns {{ days: number, through_day: string } | null}
 */
export function commitStreak(db, userId, currentDay) {
  if (!currentDay) return null;
  const rows = db
    .prepare(
      `SELECT client_day
       FROM daily_activity
       WHERE user_id = ? AND client_day <= ?
       GROUP BY client_day
       HAVING SUM(commits) > 0
       ORDER BY client_day DESC`,
    )
    .all(userId, currentDay);
  if (!rows.length) return null;

  const throughDay = rows[0].client_day;
  let days = 0;
  let expectedDay = throughDay;
  for (const row of rows) {
    if (row.client_day !== expectedDay) break;
    days += 1;
    expectedDay = previousDay(expectedDay);
    if (!expectedDay) break;
  }
  return { days, through_day: throughDay };
}

function getCard(payload, type) {
  return payload.cards?.find((card) => card.type === type && card.enabled) ?? null;
}

function sumNumber(total, value) {
  return total + (Number.isFinite(Number(value)) ? Number(value) : 0);
}

function commitDetails(card) {
  if (!Array.isArray(card.data?.commit_details)) return [];
  return card.data.commit_details
    .map((commit) => {
      if (!commit || typeof commit !== "object" || Array.isArray(commit)) return null;
      const id = String(commit.id ?? "").trim();
      if (!/^[a-f0-9]{64}$/.test(id)) return null;
      return {
        id,
        committed_at: typeof commit.committed_at === "string" ? commit.committed_at : null,
        files_changed: Math.max(0, Number(commit.files_changed) || 0),
        insertions: Math.max(0, Number(commit.insertions) || 0),
        deletions: Math.max(0, Number(commit.deletions) || 0),
      };
    })
    .filter(Boolean);
}

function recordDailyCommits(db, userId, clientDay, card, receivedAt) {
  const details = commitDetails(card);
  if (!details.length) return;
  const insert = db.prepare(
    `INSERT INTO daily_commits (
       user_id, client_day, commit_id, files_changed, insertions, deletions,
       committed_at, updated_at
     )
     VALUES (?, ?, ?, ?, ?, ?, ?, ?)
     ON CONFLICT(user_id, client_day, commit_id) DO UPDATE SET
       files_changed = excluded.files_changed,
       insertions = excluded.insertions,
       deletions = excluded.deletions,
       committed_at = COALESCE(excluded.committed_at, daily_commits.committed_at),
       updated_at = excluded.updated_at`,
  );
  for (const commit of details) {
    insert.run(
      userId,
      clientDay,
      commit.id,
      commit.files_changed,
      commit.insertions,
      commit.deletions,
      commit.committed_at,
      receivedAt,
    );
  }
}

function mergeGitStats(rows, chosenDay, chosenTimezone) {
  // No uncommitted_* keys: only committed work counts, so uncommitted figures
  // from older clients are dropped rather than merged into the feed.
  const stats = {
    commits: 0,
    files_changed: 0,
    insertions: 0,
    deletions: 0,
    repos_touched: 0,
  };
  let found = false;
  const seenCommits = new Set();
  for (const row of rows) {
    if (row.client_day !== chosenDay) continue;
    if (chosenTimezone && row.payload.day_timezone && row.payload.day_timezone !== chosenTimezone) {
      continue;
    }
    const card = getCard(row.payload, "git_stats");
    if (!card) continue;
    found = true;
    const details = commitDetails(card);
    if (details.length) {
      for (const commit of details) {
        if (seenCommits.has(commit.id)) continue;
        seenCommits.add(commit.id);
        stats.commits += 1;
        stats.files_changed += commit.files_changed;
        stats.insertions += commit.insertions;
        stats.deletions += commit.deletions;
      }
      stats.repos_touched = sumNumber(stats.repos_touched, card.data?.repos_touched);
    } else {
      for (const key of Object.keys(stats)) {
        stats[key] = sumNumber(stats[key], card.data?.[key]);
      }
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

function chooseVibesDay(user, onlineRows, source, nowMs) {
  const timezone = user.timezone && isSupportedTimezone(user.timezone) ? user.timezone : null;
  const currentDay = timezone ? formatDayInTimezone(nowMs, timezone) : null;
  if (currentDay && onlineRows.some((row) => row.client_day === currentDay)) {
    return { day: currentDay, timezone };
  }
  return {
    day: onlineRows[0]?.client_day ?? source.client_day,
    timezone: currentDay ? timezone : null,
  };
}

function newestOnlineRowForDay(onlineRows, day, timezone) {
  return (
    onlineRows.find((row) => {
      if (row.client_day !== day) return false;
      return !timezone || !row.payload.day_timezone || row.payload.day_timezone === timezone;
    }) ??
    onlineRows.find((row) => row.client_day === day) ??
    onlineRows[0]
  );
}

function mergeUserStatuses(user, statusRows, nowMs) {
  if (!statusRows.length) {
    return {
      user: feedUser(user),
      mode: "offline",
      manual_status: null,
      day: null,
      updated_at: null,
      cards: [],
    };
  }

  const rows = statusRows.map((row) => ({ ...row, payload: JSON.parse(row.payload_json) }));
  const strongest = rows.reduce((best, row) =>
    MODE_RANK[row.mode] > MODE_RANK[best.mode] ? row : best,
  );
  const online = rows
    .filter((row) => row.mode === "online")
    .sort((a, b) => Date.parse(b.updated_at) - Date.parse(a.updated_at));
  const source = online[0] ?? rows.sort((a, b) => Date.parse(b.updated_at) - Date.parse(a.updated_at))[0];
  const { day: latestDay, timezone: chosenTimezone } = chooseVibesDay(user, online, source, nowMs);
  const cardSource = newestOnlineRowForDay(online, latestDay, chosenTimezone) ?? source;

  // Effective presence: the user is live (`online`) only if they have published
  // within the recency window. Offline/stale views still carry the last shared
  // cards so the feed can show the latest snapshot instead of zeroing activity.
  const lastSharedAt = online
    .map((row) => row.updated_at)
    .sort((a, b) => Date.parse(b) - Date.parse(a))[0];
  const snapshotAt = lastSharedAt ?? source.updated_at ?? null;
  const isFresh =
    strongest.mode === "online" && nowMs - Date.parse(lastSharedAt) <= ONLINE_WINDOW_MS;

  const cards = [];
  const gitStats = mergeGitStats(rows, latestDay, chosenTimezone);
  if (gitStats) cards.push(gitStats);
  for (const type of ["repo_aliases", "music", "weather"]) {
    const card = getCard(cardSource.payload, type);
    if (card) cards.push(card);
  }

  if (!isFresh) {
    return {
      user: feedUser(user),
      mode: "offline",
      manual_status: cardSource.payload.manual_status ?? null,
      day: latestDay,
      updated_at: snapshotAt,
      cards,
    };
  }

  return {
    user: feedUser(user),
    mode: "online",
    manual_status: cardSource.payload.manual_status ?? null,
    day: latestDay,
    updated_at: lastSharedAt,
    cards,
  };
}

/**
 * @param {import('better-sqlite3').Database} db
 * @param {{ id: string, handle: string, display_name: string }} viewer
 * @param {number} [nowMs] Reference clock for recency, injectable for tests.
 */
export function getFeed(db, viewer, nowMs = Date.now()) {
  const users = [
    viewer,
    ...db
      .prepare(
        `SELECT users.id, users.handle, users.display_name, users.timezone, users.avatar_id,
                users.avatar_kind, users.avatar_gradient_start, users.avatar_gradient_end
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
  // The authenticated viewer object carries no avatar columns, so re-read the row
  // to surface the viewer's own avatar_url / avatar_kind / gradient.
  const viewerRow =
    viewer.avatar_id === undefined
      ? db
          .prepare(
            `SELECT id, handle, display_name, timezone, avatar_id,
                    avatar_kind, avatar_gradient_start, avatar_gradient_end
             FROM users WHERE id = ?`,
          )
          .get(viewer.id) ?? viewer
      : viewer;
  const merged = [viewerRow, ...users.slice(1)].map((user) => {
    const status = mergeUserStatuses(user, statusQuery.all(user.id), nowMs);
    status.typical_churn = typicalChurn(db, user.id, status.day);
    const hasVisibleGitStats = status.cards.some((card) => card.type === "git_stats");
    const timezone = user.timezone && isSupportedTimezone(user.timezone) ? user.timezone : null;
    // The streak anchors on the live current day (not status.day, which is the
    // last published day) so it caps out future-dated rows while still keeping a
    // through-yesterday streak alive when the user hasn't committed yet today.
    const currentDay = timezone ? formatDayInTimezone(nowMs, timezone) : status.day;
    status.commit_streak = hasVisibleGitStats ? commitStreak(db, user.id, currentDay) : null;
    return status;
  });
  return { you: merged[0], friends: merged.slice(1), pulse: networkPulse(db, nowMs) };
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
 * Active (non-revoked) tokens for a user — the device list. Tokens are minted
 * one per device and labeled with the device name; last_used_at is touched on
 * every authenticated call, so it doubles as a device's last-seen.
 * @param {import('better-sqlite3').Database} db
 * @param {string} userId
 */
export function listTokens(db, userId) {
  return db
    .prepare(
      `SELECT id, label, created_at, last_used_at
       FROM auth_tokens
       WHERE user_id = ? AND revoked_at IS NULL
       ORDER BY created_at ASC, rowid ASC`,
    )
    .all(userId)
    .map((token) => ({
      token_id: token.id,
      label: token.label,
      created_at: token.created_at,
      last_used_at: token.last_used_at,
    }));
}

/**
 * Mint a fresh labeled token for the authenticated account — how an already
 * trusted credential provisions a new device (e.g. the iCloud-Keychain
 * welcome-back path) without sharing itself. Same response shape as
 * registerUser/claimDeviceLinkCode so clients reuse one decode path.
 * @param {import('better-sqlite3').Database} db
 * @param {string} userId
 * @param {string | null} [label]
 */
export function mintDeviceToken(db, userId, label = null) {
  const user = db
    .prepare("SELECT * FROM users WHERE id = ? AND disabled_at IS NULL")
    .get(userId);
  if (!user) throw new RelayError("unauthorized", "Authentication is required.", 401);
  const token = createToken(db, userId, label);
  return { user: registeredUser(user), token };
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

const PNG_SIGNATURE = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);

/**
 * Validate raw upload bytes as a PNG and read its pixel dimensions from the
 * IHDR chunk — pure JS, no native deps. Enforces the PNG signature, a byte
 * cap, and a sane max dimension. Returns `{ width, height, byteSize }`.
 * @param {Buffer | Uint8Array} input
 * @returns {{ width: number, height: number, byteSize: number }}
 */
export function validatePng(input) {
  const bytes = Buffer.isBuffer(input) ? input : Buffer.from(input);
  if (bytes.length === 0) {
    throw new RelayError("invalid_image", "Image body is empty.", 400);
  }
  if (bytes.length > MAX_AVATAR_BYTES) {
    throw new RelayError("payload_too_large", "Image is too large.", 413);
  }
  // 8-byte signature, then the first chunk must be IHDR (length 13).
  if (bytes.length < 33 || !bytes.subarray(0, 8).equals(PNG_SIGNATURE)) {
    throw new RelayError("invalid_image", "Image must be a PNG.", 400);
  }
  // Chunk layout: [4 len][4 type][...data][4 crc]. IHDR starts at offset 8.
  if (bytes.toString("ascii", 12, 16) !== "IHDR") {
    throw new RelayError("invalid_image", "Image must be a PNG.", 400);
  }
  const width = bytes.readUInt32BE(16);
  const height = bytes.readUInt32BE(20);
  if (
    width < 1 ||
    height < 1 ||
    width > MAX_AVATAR_DIMENSION ||
    height > MAX_AVATAR_DIMENSION
  ) {
    throw new RelayError("invalid_image", "Image dimensions are out of range.", 400);
  }
  return { width, height, byteSize: bytes.length };
}

// Chunks worth keeping when rebuilding a PNG. We drop everything else — text
// (tEXt/iTXt/zTXt), EXIF (eXIf), timestamps (tIME), and any unknown/appended
// chunks — so an untrusted client cannot smuggle arbitrary bytes into a file we
// serve. Includes the core image chunks plus the rendering-critical ancillary
// ones (palette, transparency, gamma/color) needed to display correctly.
const PNG_KEEP_CHUNKS = new Set([
  "IHDR",
  "PLTE",
  "IDAT",
  "IEND",
  "tRNS",
  "gAMA",
  "cHRM",
  "sRGB",
  "iCCP",
  "sBIT",
  "bKGD",
]);

/**
 * Rebuild a validated PNG from only its essential chunks, dropping metadata and
 * any trailing/unknown bytes — pure JS, no native deps. The input must already
 * have passed {@link validatePng}; malformed chunk framing throws invalid_image.
 * @param {Buffer | Uint8Array} input
 * @returns {Buffer}
 */
export function sanitizePng(input) {
  const bytes = Buffer.isBuffer(input) ? input : Buffer.from(input);
  const out = [Buffer.from(PNG_SIGNATURE)];
  let offset = PNG_SIGNATURE.length;
  let sawIend = false;
  while (offset + 8 <= bytes.length) {
    const length = bytes.readUInt32BE(offset);
    const dataStart = offset + 8;
    const chunkEnd = dataStart + length + 4; // data + 4-byte CRC
    if (chunkEnd > bytes.length) {
      throw new RelayError("invalid_image", "Image is malformed.", 400);
    }
    const type = bytes.toString("ascii", offset + 4, offset + 8);
    if (PNG_KEEP_CHUNKS.has(type)) {
      out.push(bytes.subarray(offset, chunkEnd));
    }
    offset = chunkEnd;
    if (type === "IEND") {
      sawIend = true;
      break; // anything after IEND is appended payload; discard it
    }
  }
  if (!sawIend) {
    throw new RelayError("invalid_image", "Image is malformed.", 400);
  }
  return Buffer.concat(out);
}

/**
 * Mint a short, URL-safe slug for an avatar asset, retried on the rare PK
 * collision. ~12 chars from 9 random bytes (base64url, no padding).
 * @param {import('better-sqlite3').Database} db
 * @param {number} [bytes]
 * @returns {string}
 */
export function newShortId(db, bytes = 9) {
  for (let i = 0; i < 5; i += 1) {
    const id = randomBytes(bytes).toString("base64url");
    const hit = db.prepare("SELECT 1 FROM avatars WHERE id = ?").get(id);
    if (!hit) return id;
  }
  throw new RelayError("internal", "Could not allocate avatar id.", 500);
}

/**
 * Store a generated avatar for a user: mint a slug, write the bytes via the
 * storage adapter, record the row, and point users.avatar_id at it. The old
 * row/asset is kept as immutable history (no delete on regenerate), so the
 * minted URL is safe to cache `immutable`.
 * @param {import('better-sqlite3').Database} db
 * @param {{ id: string }} user
 * @param {{ bytes: Buffer | Uint8Array, contentType: string, width: number, height: number, prompt?: string | null, style?: string | null }} input
 * @returns {{ id: string, avatar_url: string }}
 */
export function setUserAvatar(db, user, { bytes, contentType, width, height, prompt = null, style = null }) {
  const store = getAvatarStore();
  const cleanPrompt =
    prompt == null ? null : String(prompt).trim().slice(0, MAX_AVATAR_PROMPT_LENGTH) || null;
  const cleanStyle =
    style == null ? null : String(style).trim().slice(0, MAX_AVATAR_STYLE_LENGTH) || null;

  return writeTx(db, () => {
    const id = newShortId(db);
    // Write bytes first; if the row insert fails the orphaned file is harmless
    // (it is unreferenced and overwritten only by a future slug, which is unique).
    store.put(id, bytes, contentType);
    db.prepare(
      `INSERT INTO avatars (
         id, user_id, store, content_type, width, height, byte_size, prompt, style, created_at
       )
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    ).run(
      id,
      user.id,
      store.kind,
      contentType,
      width,
      height,
      bytes.length,
      cleanPrompt,
      cleanStyle,
      now(),
    );
    db.prepare(
      "UPDATE users SET avatar_id = ?, avatar_kind = 'image', updated_at = ? WHERE id = ?",
    ).run(id, now(), user.id);
    return { id, avatar_url: store.urlFor(id) };
  });
}

/**
 * Set a user's avatar to a two-color gradient (rendered client-side; no asset
 * stored). Selecting a gradient supersedes any AI image — `avatar_kind` becomes
 * the explicit selector and `avatar_id` is left intact but no longer consulted.
 * @param {import('better-sqlite3').Database} db
 * @param {{ id: string }} user
 * @param {{ start: unknown, end: unknown }} input
 * @returns {{ avatar_kind: string, avatar_gradient: { start: string, end: string }, avatar_url: string | null }}
 */
export function setUserGradient(db, user, { start, end }) {
  const cleanStart = validateHexColor(start, "Gradient start");
  const cleanEnd = validateHexColor(end, "Gradient end");

  return writeTx(db, () => {
    db.prepare(
      `UPDATE users
       SET avatar_kind = 'gradient',
           avatar_gradient_start = ?,
           avatar_gradient_end = ?,
           updated_at = ?
       WHERE id = ?`,
    ).run(cleanStart, cleanEnd, now(), user.id);
    const row = db
      .prepare("SELECT avatar_id, avatar_kind, avatar_gradient_start, avatar_gradient_end FROM users WHERE id = ?")
      .get(user.id);
    return {
      avatar_kind: row.avatar_kind,
      avatar_gradient: avatarGradientFor(row),
      avatar_url: avatarUrlFor(row),
    };
  });
}

/**
 * Clear a user's current avatar (revert to initials): drops the image pointer,
 * the kind selector, and any gradient colors in one write. Avatar history rows
 * are retained.
 * @param {import('better-sqlite3').Database} db
 * @param {{ id: string }} user
 * @returns {{ ok: true }}
 */
export function clearUserAvatar(db, user) {
  db.prepare(
    `UPDATE users
     SET avatar_id = NULL,
         avatar_kind = NULL,
         avatar_gradient_start = NULL,
         avatar_gradient_end = NULL,
         updated_at = ?
     WHERE id = ?`,
  ).run(now(), user.id);
  return { ok: true };
}
