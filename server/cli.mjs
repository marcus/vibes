#!/usr/bin/env node
// Minimal bootstrap/admin CLI for the Vibes relay. Prints JSON so agents can
// parse it. Run `node cli.mjs <command>` from the server directory.
import { openDb } from "./src/lib/server/db.js";
import { createInvite, createToken, createUser } from "./src/lib/server/relay.js";

function arg(name) {
  const i = process.argv.indexOf(`--${name}`);
  return i === -1 ? undefined : process.argv[i + 1];
}

// Handles are stored lowercased, so look them up the same way.
function userByHandle(handle) {
  return db
    .prepare("SELECT id FROM users WHERE handle = ?")
    .get(String(handle ?? "").trim().toLowerCase());
}

function out(value) {
  process.stdout.write(`${JSON.stringify(value, null, 2)}\n`);
}

const db = openDb(process.env.VIBES_DB_PATH ?? "data/vibes.sqlite");
const [, , group, action] = process.argv;
const cmd = `${group} ${action}`;

try {
  if (cmd === "db migrate") {
    out({ ok: true, migrated: true });
  } else if (cmd === "users create") {
    out({ user: createUser(db, { handle: arg("handle"), displayName: arg("display-name") }) });
  } else if (cmd === "tokens create") {
    const user = userByHandle(arg("user"));
    if (!user) throw new Error(`no such user: ${arg("user")}`);
    out({ token: createToken(db, user.id, arg("label")) });
  } else if (cmd === "invites create") {
    const user = userByHandle(arg("user"));
    if (!user) throw new Error(`no such user: ${arg("user")}`);
    out({ invite: createInvite(db, user.id) });
  } else {
    out({ ok: false, error: "unknown_command", usage: ["db migrate", "users create", "tokens create", "invites create"] });
    process.exit(2);
  }
} catch (err) {
  out({ ok: false, error: String(err.message ?? err) });
  process.exit(1);
}
