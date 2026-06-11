import { json } from "@sveltejs/kit";
import { getDb } from "$lib/server/db.js";
import { checkRateLimit, errorJson, readJson } from "$lib/server/http.js";
import { claimDeviceLinkCode } from "$lib/server/relay.js";

// Unauthenticated by design: the new Mac has no token yet — the code is the
// credential. The tight rate limit is the brute-force guard on top of the
// code's single use and short TTL.
export async function POST(event) {
  try {
    checkRateLimit(event, "link-codes:claim", 10);
    const body = await readJson(event.request);
    const { user, token } = claimDeviceLinkCode(getDb(), body?.code, {
      deviceLabel: body?.device_label ?? body?.deviceLabel ?? "Mac",
    });
    return json({ user, token: token.token }, { status: 201 });
  } catch (err) {
    return errorJson(err);
  }
}
