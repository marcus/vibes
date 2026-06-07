import { json } from "@sveltejs/kit";
import { getDb } from "$lib/server/db.js";
import { errorJson, requireAuth, readJson } from "$lib/server/http.js";
import { revokeToken } from "$lib/server/relay.js";

export async function POST(event) {
  try {
    const auth = requireAuth(event.request);
    const body = await readJson(event.request);
    return json(revokeToken(getDb(), auth.user.id, body.token_id));
  } catch (err) {
    return errorJson(err);
  }
}

