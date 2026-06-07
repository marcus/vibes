import { json } from "@sveltejs/kit";
import { getDb } from "$lib/server/db.js";
import { checkRateLimit, errorJson, readJson } from "$lib/server/http.js";
import { createUser } from "$lib/server/relay.js";

export async function POST(event) {
  try {
    checkRateLimit(event, "users:create", 10);
    const body = await readJson(event.request);
    const user = createUser(getDb(), {
      handle: body.handle,
      displayName: body.display_name,
    });
    return json({ user }, { status: 201 });
  } catch (err) {
    return errorJson(err);
  }
}

