import { json } from "@sveltejs/kit";
import { getDb } from "$lib/server/db.js";
import { checkRateLimit, errorJson, readJson } from "$lib/server/http.js";
import { registerUser } from "$lib/server/relay.js";

export async function POST(event) {
  try {
    checkRateLimit(event, "register:create", 10);
    const body = await readJson(event.request);
    const { user, token } = registerUser(getDb(), {
      displayName: body?.display_name ?? body?.displayName,
      deviceLabel: body?.device_label ?? body?.deviceLabel ?? "Mac",
    });
    return json({ user, token: token.token }, { status: 201 });
  } catch (err) {
    return errorJson(err);
  }
}
