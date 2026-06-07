import { json } from "@sveltejs/kit";
import { getDb } from "$lib/server/db.js";
import { checkRateLimit, errorJson, requireAuth, readJson } from "$lib/server/http.js";
import { upsertStatus } from "$lib/server/relay.js";

export async function POST(event) {
  try {
    checkRateLimit(event, "status:post", 120);
    const auth = requireAuth(event.request);
    const body = await readJson(event.request, { maxBytes: 32 * 1024 });
    return json(upsertStatus(getDb(), auth.user, body));
  } catch (err) {
    return errorJson(err);
  }
}
