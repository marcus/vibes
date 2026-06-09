import { json } from "@sveltejs/kit";
import { checkRateLimit, errorJson, requireAuth } from "$lib/server/http.js";

export async function GET(event) {
  try {
    checkRateLimit(event, "me:read", 120);
    const auth = requireAuth(event.request);
    return json({
      user: {
        id: auth.user.id,
        handle: auth.user.handle,
        display_name: auth.user.display_name,
        timezone: auth.user.timezone ?? null,
      },
    });
  } catch (err) {
    return errorJson(err);
  }
}
