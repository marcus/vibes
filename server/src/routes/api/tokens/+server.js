import { json } from "@sveltejs/kit";
import { getDb } from "$lib/server/db.js";
import { checkRateLimit, errorJson, readJson, requireAuth } from "$lib/server/http.js";
import { mintDeviceToken } from "$lib/server/relay.js";

// Mint a fresh labeled token for the caller's account. Sibling of
// ./revoke — together they are the device-token lifecycle.
export async function POST(event) {
  try {
    checkRateLimit(event, "tokens:create", 10);
    const auth = requireAuth(event.request);
    const body = await readJson(event.request);
    const { user, token } = mintDeviceToken(
      getDb(),
      auth.user.id,
      body?.label ?? body?.device_label ?? null,
    );
    return json({ user, token: token.token }, { status: 201 });
  } catch (err) {
    return errorJson(err);
  }
}
