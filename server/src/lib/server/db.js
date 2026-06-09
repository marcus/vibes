import Database from "better-sqlite3";
import { mkdirSync } from "node:fs";
import { dirname } from "node:path";

/**
 * Versioned schema migrations, applied in order. Add a migration by appending a
 * new `{ version, name, sql }` entry — never edit or renumber an existing one.
 * `migrate()` records applied versions in `schema_migrations` and is idempotent.
 */
const MIGRATIONS = [
  {
    version: 1,
    name: "init",
    sql: `
      CREATE TABLE users (
        id TEXT PRIMARY KEY,
        handle TEXT NOT NULL UNIQUE,
        display_name TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        disabled_at TEXT
      );

      CREATE TABLE auth_tokens (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        token_hash TEXT NOT NULL UNIQUE,
        label TEXT,
        created_at TEXT NOT NULL,
        last_used_at TEXT,
        revoked_at TEXT
      );

      CREATE TABLE friendships (
        user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        friend_user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        state TEXT NOT NULL DEFAULT 'accepted',
        created_at TEXT NOT NULL,
        PRIMARY KEY (user_id, friend_user_id)
      );

      CREATE TABLE invites (
        id TEXT PRIMARY KEY,
        code_hash TEXT NOT NULL UNIQUE,
        creator_user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        accepted_by_user_id TEXT REFERENCES users(id),
        created_at TEXT NOT NULL,
        accepted_at TEXT,
        revoked_at TEXT,
        expires_at TEXT
      );

      CREATE TABLE statuses (
        user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        device_id TEXT NOT NULL,
        device_label TEXT,
        mode TEXT NOT NULL,
        client_day TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        schema_version INTEGER NOT NULL DEFAULT 1,
        updated_at TEXT NOT NULL,
        server_received_at TEXT NOT NULL,
        PRIMARY KEY (user_id, device_id)
      );
    `,
  },
  {
    version: 2,
    name: "admin_sessions",
    sql: `
      CREATE TABLE sessions (
        id TEXT PRIMARY KEY,
        token_hash TEXT NOT NULL UNIQUE,
        kind TEXT NOT NULL,                 -- 'admin' for v1; 'user' reserved for self-serve
        user_id TEXT REFERENCES users(id) ON DELETE CASCADE,
        created_at TEXT NOT NULL,
        last_seen_at TEXT,
        expires_at TEXT NOT NULL
      );

      CREATE INDEX idx_sessions_expires_at ON sessions(expires_at);

      CREATE TABLE admin_audit (
        id TEXT PRIMARY KEY,
        action TEXT NOT NULL,
        target_type TEXT,
        target_id TEXT,
        detail TEXT,
        created_at TEXT NOT NULL
      );

      CREATE INDEX idx_admin_audit_created_at ON admin_audit(created_at);
    `,
  },
  {
    version: 3,
    name: "user_timezone",
    sql: `
      ALTER TABLE users ADD COLUMN timezone TEXT;
    `,
  },
];

/**
 * Apply any pending migrations. Safe to call on every boot and safe to run from
 * two processes at once: the work happens inside one IMMEDIATE transaction that
 * re-reads applied versions after taking the write lock, so a second process
 * simply finds nothing to do.
 * @param {import('better-sqlite3').Database} db
 * @returns {number[]} versions applied by this call
 */
export function migrate(db) {
  const apply = db.transaction(() => {
    db.exec(
      `CREATE TABLE IF NOT EXISTS schema_migrations (
         version INTEGER PRIMARY KEY,
         name TEXT NOT NULL,
         applied_at TEXT NOT NULL
       );`,
    );
    const applied = new Set(
      db.prepare("SELECT version FROM schema_migrations").all().map((r) => r.version),
    );
    const done = [];
    for (const migration of MIGRATIONS) {
      if (applied.has(migration.version)) continue;
      db.exec(migration.sql);
      db.prepare(
        "INSERT INTO schema_migrations (version, name, applied_at) VALUES (?, ?, ?)",
      ).run(migration.version, migration.name, new Date().toISOString());
      done.push(migration.version);
    }
    return done;
  });

  return apply.immediate();
}

/**
 * Open a database with the single-writer pragmas, then migrate.
 * Pass ":memory:" for tests.
 *
 * Single-writer pattern: WAL keeps reads concurrent while writes serialize;
 * busy_timeout makes a second writer (e.g. the CLI) wait for the lock instead
 * of erroring; writes go through IMMEDIATE transactions (see writeTx) so they
 * take the write lock up front. better-sqlite3 is synchronous, so within the
 * relay process there is only ever one writer.
 * @param {string} path
 * @returns {import('better-sqlite3').Database}
 */
export function openDb(path) {
  if (path !== ":memory:") {
    mkdirSync(dirname(path), { recursive: true });
  }
  const db = new Database(path);
  // busy_timeout must be set first: setting journal_mode = WAL and running
  // migrations take a write lock, and on a fresh file two processes can race
  // there. With the timeout already in place they wait instead of erroring.
  db.pragma("busy_timeout = 5000");
  db.pragma("journal_mode = WAL");
  db.pragma("synchronous = NORMAL");
  db.pragma("foreign_keys = ON");
  migrate(db);
  return db;
}

/**
 * Run a multi-statement write inside an IMMEDIATE transaction so it grabs the
 * write lock up front and is atomic. Single-statement writes can run directly;
 * busy_timeout covers cross-process contention either way.
 * @template T
 * @param {import('better-sqlite3').Database} db
 * @param {() => T} fn
 * @returns {T}
 */
export function writeTx(db, fn) {
  return db.transaction(fn).immediate();
}

/** @type {import('better-sqlite3').Database | null} */
let singleton = null;
let shutdownHooked = false;

/** Checkpoint the WAL and close cleanly on shutdown so no frames are stranded. */
function hookShutdown(db) {
  if (shutdownHooked) return;
  shutdownHooked = true;
  let closed = false;
  const close = () => {
    if (closed) return;
    closed = true;
    try {
      db.pragma("wal_checkpoint(TRUNCATE)");
      db.close();
    } catch {
      // best effort on the way out
    }
  };
  // adapter-node emits this after the HTTP server has stopped accepting traffic.
  process.once("sveltekit:shutdown", close);
  process.once("exit", close);
}

/**
 * Shared process-wide database handle for the running relay — the single writer.
 * @returns {import('better-sqlite3').Database}
 */
export function getDb() {
  if (singleton) return singleton;
  const path = process.env.VIBES_DB_PATH ?? "data/vibes.sqlite";
  singleton = openDb(path);
  hookShutdown(singleton);
  return singleton;
}
