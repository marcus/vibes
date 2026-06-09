import { json } from "@sveltejs/kit";
import { getDb } from "$lib/server/db.js";
import { checkRateLimit, errorJson, requireAuth } from "$lib/server/http.js";
import { HOUSE_STYLE, avatarUrlFor } from "$lib/server/relay.js";

export async function GET(event) {
  try {
    checkRateLimit(event, "me:read", 120);
    const auth = requireAuth(event.request);
    // The token-auth user row carries no avatar_id; re-read it so /api/me can
    // surface the caller's current avatar_url.
    const row = getDb()
      .prepare("SELECT avatar_id FROM users WHERE id = ?")
      .get(auth.user.id);
    return json({
      user: {
        id: auth.user.id,
        handle: auth.user.handle,
        display_name: auth.user.display_name,
        timezone: auth.user.timezone ?? null,
        avatar_url: avatarUrlFor(row),
      },
      house_style: HOUSE_STYLE,
    });
  } catch (err) {
    return errorJson(err);
  }
}
