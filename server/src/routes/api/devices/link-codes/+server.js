import { json } from "@sveltejs/kit";
import { getDb } from "$lib/server/db.js";
import { checkRateLimit, errorJson, readJson, requireAuth } from "$lib/server/http.js";
import { createDeviceLinkCode } from "$lib/server/relay.js";

export async function POST(event) {
  try {
    checkRateLimit(event, "link-codes:create", 10);
    const auth = requireAuth(event.request);
    await readJson(event.request);
    const created = createDeviceLinkCode(getDb(), auth.user.id);
    return json(created, { status: 201 });
  } catch (err) {
    return errorJson(err);
  }
}
