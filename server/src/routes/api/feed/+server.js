import { json } from "@sveltejs/kit";
import { getDb } from "$lib/server/db.js";
import { errorJson, requireAuth } from "$lib/server/http.js";
import { getFeed } from "$lib/server/relay.js";

export function GET(event) {
  try {
    const auth = requireAuth(event.request);
    return json(getFeed(getDb(), auth.user));
  } catch (err) {
    return errorJson(err);
  }
}

