import { execFile } from "node:child_process";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { promisify } from "node:util";
import { afterAll, expect, it } from "vitest";
import { openDb } from "../src/lib/server/db.js";

const run = promisify(execFile);

const dir = mkdtempSync(join(tmpdir(), "vibes-sw-"));
const dbPath = join(dir, "vibes.sqlite");

afterAll(() => rmSync(dir, { recursive: true, force: true }));

// Spawns real OS processes that all write to one SQLite file at once. This is
// the case better-sqlite3 cannot serialize on its own; WAL + busy_timeout +
// migration-under-lock must. Every write should land, none should SQLITE_BUSY.
it("serializes concurrent writes from many processes without loss", async () => {
  const N = 12;
  const results = await Promise.allSettled(
    Array.from({ length: N }, (_, i) =>
      run(
        "node",
        ["cli.mjs", "users", "create", "--handle", `u${i}`, "--display-name", `U${i}`],
        { env: { ...process.env, VIBES_DB_PATH: dbPath } },
      ),
    ),
  );

  const failed = results.filter((r) => r.status === "rejected");
  expect(failed, JSON.stringify(failed.map((f) => String(f.reason)), null, 2)).toHaveLength(0);

  const db = openDb(dbPath);
  expect(db.prepare("SELECT count(*) AS n FROM users").get().n).toBe(N);
}, 30000);
