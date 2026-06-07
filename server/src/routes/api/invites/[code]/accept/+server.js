import { json } from "@sveltejs/kit";
import { getDb } from "$lib/server/db.js";
import { errorJson, requireAuth } from "$lib/server/http.js";
import { acceptInvite } from "$lib/server/relay.js";

export function POST(event) {
  try {
    const auth = requireAuth(event.request);
    const accepted = acceptInvite(getDb(), event.params.code, {
      acceptingUserId: auth.user.id,
    });
    return json(accepted);
  } catch (err) {
    return errorJson(err);
  }
}
