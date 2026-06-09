import { json } from "@sveltejs/kit";
import { getDb } from "$lib/server/db.js";
import { checkRateLimit, errorJson, readJson, requireAuth } from "$lib/server/http.js";
import { setUserGradient } from "$lib/server/relay.js";

export async function PUT(event) {
  try {
    checkRateLimit(event, "avatar:gradient", 30);
    const auth = requireAuth(event.request);
    const body = await readJson(event.request);
    const result = setUserGradient(getDb(), auth.user, {
      start: body?.start,
      end: body?.end,
    });
    return json(result);
  } catch (err) {
    return errorJson(err);
  }
}
