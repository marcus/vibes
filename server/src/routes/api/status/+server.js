import { json } from "@sveltejs/kit";
import { getDb } from "$lib/server/db.js";
import { checkRateLimit, errorJson, requireAuth, readJson } from "$lib/server/http.js";
import { MAX_STATUS_BYTES, upsertStatus } from "$lib/server/relay.js";

export async function POST(event) {
  try {
    checkRateLimit(event, "status:post", 120);
    const auth = requireAuth(event.request);
    const body = await readJson(event.request, { maxBytes: MAX_STATUS_BYTES });
    return json(upsertStatus(getDb(), auth.user, body));
  } catch (err) {
    return errorJson(err);
  }
}
