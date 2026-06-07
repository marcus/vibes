import { json } from "@sveltejs/kit";
import { getDb } from "$lib/server/db.js";
import { errorJson, requireAuth } from "$lib/server/http.js";
import { revokeInvite } from "$lib/server/relay.js";

export function POST(event) {
  try {
    const auth = requireAuth(event.request);
    return json(revokeInvite(getDb(), auth.user.id, event.params.id));
  } catch (err) {
    return errorJson(err);
  }
}

