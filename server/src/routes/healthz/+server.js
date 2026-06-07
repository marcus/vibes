import { json } from "@sveltejs/kit";
import { getDb } from "$lib/server/db.js";

export function GET() {
  // Touch the database so the health check fails loudly if migrations or the
  // SQLite file are broken.
  getDb().prepare("SELECT 1").get();
  return json({ ok: true, service: "vibes-relay" });
}
