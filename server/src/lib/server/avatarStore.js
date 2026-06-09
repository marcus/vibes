import { mkdirSync, writeFileSync, rmSync } from "node:fs";
import { join } from "node:path";
import { RelayError } from "./relay.js";

/**
 * Avatar storage is isolated behind a tiny adapter interface so the byte store
 * can swap (filesystem today, S3/R2 later) without touching relay logic. Each
 * adapter implements:
 *   put(id, bytes, contentType) -> void
 *   remove(id) -> void
 *   urlFor(id) -> string        // public, cache-immutable URL for the slug
 *   kind: string                // value persisted in avatars.store
 */

/**
 * Filesystem store: writes `${VIBES_AVATAR_DIR}/<id>.png` (served by an nginx
 * alias on the VPS / the static dir locally) and builds public URLs by appending
 * the slug to `VIBES_AVATAR_BASE_URL`.
 */
export class FilesystemAvatarStore {
  /** @param {{ dir: string, baseUrl: string }} options */
  constructor({ dir, baseUrl }) {
    this.kind = "filesystem";
    this.dir = dir;
    this.baseUrl = baseUrl.replace(/\/+$/, "");
    // Create the directory eagerly, mirroring openDb's mkdirSync(recursive).
    mkdirSync(this.dir, { recursive: true });
  }

  /**
   * @param {string} id
   * @param {Buffer | Uint8Array} bytes
   * @param {string} _contentType
   */
  put(id, bytes, _contentType) {
    writeFileSync(join(this.dir, `${id}.png`), bytes);
  }

  /** @param {string} id */
  remove(id) {
    rmSync(join(this.dir, `${id}.png`), { force: true });
  }

  /** @param {string} id */
  urlFor(id) {
    return `${this.baseUrl}/${id}.png`;
  }
}

/**
 * S3/R2 store: interface placeholder until bucket credentials are added. Same
 * put/remove/urlFor signatures; throws until configured.
 */
export class S3AvatarStore {
  constructor() {
    this.kind = "s3";
  }

  put() {
    throw new RelayError("internal", "S3 avatar store is not configured.", 500);
  }

  remove() {
    throw new RelayError("internal", "S3 avatar store is not configured.", 500);
  }

  urlFor() {
    throw new RelayError("internal", "S3 avatar store is not configured.", 500);
  }
}

/** @type {(FilesystemAvatarStore | S3AvatarStore) | null} */
let singleton = null;

/**
 * Process-wide avatar store, chosen by env at first use (mirrors how db.js reads
 * VIBES_DB_PATH). `VIBES_AVATAR_STORE` selects the adapter; `filesystem` default.
 * @returns {FilesystemAvatarStore | S3AvatarStore}
 */
export function getAvatarStore() {
  if (singleton) return singleton;
  const kind = (process.env.VIBES_AVATAR_STORE ?? "filesystem").trim().toLowerCase();
  if (kind === "s3") {
    singleton = new S3AvatarStore();
    return singleton;
  }
  const dir = process.env.VIBES_AVATAR_DIR ?? "data/avatars";
  const baseUrl = process.env.VIBES_AVATAR_BASE_URL ?? "http://localhost:3136/avatars";
  // The defaults are dev-only: in production the localhost URL is unreachable and
  // the relative dir likely won't match what nginx serves, so every avatar 404s.
  // Warn loudly so a missing systemd Environment line is an obvious, fast failure
  // rather than a silent misconfiguration.
  if (process.env.NODE_ENV === "production") {
    if (!process.env.VIBES_AVATAR_BASE_URL) {
      console.warn(
        "[avatarStore] VIBES_AVATAR_BASE_URL is unset in production; falling back to the dev localhost URL — uploaded avatars will not be reachable. Set it in the systemd unit / server/.env.local.",
      );
    }
    if (!process.env.VIBES_AVATAR_DIR) {
      console.warn(
        "[avatarStore] VIBES_AVATAR_DIR is unset in production; falling back to the dev default 'data/avatars', which nginx likely does not serve. Set it in the systemd unit / server/.env.local.",
      );
    }
  }
  singleton = new FilesystemAvatarStore({ dir, baseUrl });
  return singleton;
}

/** Reset the cached store. Tests use this after pointing env at a temp dir. */
export function resetAvatarStore() {
  singleton = null;
}
