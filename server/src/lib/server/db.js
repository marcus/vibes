import Database from "better-sqlite3";
import { mkdirSync } from "node:fs";
import { dirname } from "node:path";

/**
 * Schema migrations applied in order. Each runs once; `db migrate` is
 * idempotent because applied versions are recorded in `schema_migrations`.
 */
const MIGRATIONS = [
  {
    version: 1,
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
];

/**
 * Apply any pending migrations. Safe to call on every boot.
 * @param {import('better-sqlite3').Database} db
 */
export function migrate(db) {
  db.exec(
    `CREATE TABLE IF NOT EXISTS schema_migrations (
       version INTEGER PRIMARY KEY,
       applied_at TEXT NOT NULL
     );`,
  );

  const applied = new Set(
    db
      .prepare("SELECT version FROM schema_migrations")
      .all()
      .map((row) => row.version),
  );

  const run = db.transaction(() => {
    for (const migration of MIGRATIONS) {
      if (applied.has(migration.version)) continue;
      db.exec(migration.sql);
      db.prepare(
        "INSERT INTO schema_migrations (version, applied_at) VALUES (?, ?)",
      ).run(migration.version, new Date().toISOString());
    }
  });
  run();
}

/**
 * Open a database, enable WAL + foreign keys, and migrate.
 * Pass ":memory:" for tests.
 * @param {string} path
 * @returns {import('better-sqlite3').Database}
 */
export function openDb(path) {
  if (path !== ":memory:") {
    mkdirSync(dirname(path), { recursive: true });
  }
  const db = new Database(path);
  db.pragma("journal_mode = WAL");
  db.pragma("foreign_keys = ON");
  migrate(db);
  return db;
}

/** @type {import('better-sqlite3').Database | null} */
let singleton = null;

/**
 * Shared process-wide database handle for the running relay.
 * @returns {import('better-sqlite3').Database}
 */
export function getDb() {
  if (singleton) return singleton;
  const path = process.env.VIBES_DB_PATH ?? "data/vibes.sqlite";
  singleton = openDb(path);
  return singleton;
}
