import { json } from "@sveltejs/kit";
import { getDb } from "$lib/server/db.js";
import { checkRateLimit, errorJson, requireAuth } from "$lib/server/http.js";
import { listTokens } from "$lib/server/relay.js";

export async function GET(event) {
  try {
    checkRateLimit(event, "devices:list", 60);
    const auth = requireAuth(event.request);
    const devices = listTokens(getDb(), auth.user.id).map((device) => ({
      ...device,
      current: device.token_id === auth.token_id,
    }));
    return json({ devices });
  } catch (err) {
    return errorJson(err);
  }
}
