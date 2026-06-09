import { json } from "@sveltejs/kit";
import { getDb } from "$lib/server/db.js";
import { checkRateLimit, errorJson, requireAuth } from "$lib/server/http.js";
import { HOUSE_STYLE, avatarGradientFor, avatarUrlFor } from "$lib/server/relay.js";

export async function GET(event) {
  try {
    checkRateLimit(event, "me:read", 120);
    const auth = requireAuth(event.request);
    // The token-auth user row carries no avatar columns; re-read them so /api/me
    // can surface the caller's current avatar_url / avatar_kind / gradient.
    const row = getDb()
      .prepare(
        `SELECT avatar_id, avatar_kind, avatar_gradient_start, avatar_gradient_end
         FROM users WHERE id = ?`,
      )
      .get(auth.user.id);
    return json({
      user: {
        id: auth.user.id,
        handle: auth.user.handle,
        display_name: auth.user.display_name,
        timezone: auth.user.timezone ?? null,
        avatar_url: avatarUrlFor(row),
        avatar_kind: row?.avatar_kind ?? null,
        avatar_gradient: avatarGradientFor(row),
      },
      house_style: HOUSE_STYLE,
    });
  } catch (err) {
    return errorJson(err);
  }
}
