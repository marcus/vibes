import { json } from "@sveltejs/kit";
import { getDb } from "$lib/server/db.js";
import { errorJson, requireAuth, readJson } from "$lib/server/http.js";
import { createInvite, listInvites } from "$lib/server/relay.js";

export async function GET(event) {
  try {
    const auth = requireAuth(event.request);
    return json({ invites: listInvites(getDb(), auth.user.id) });
  } catch (err) {
    return errorJson(err);
  }
}

export async function POST(event) {
  try {
    const auth = requireAuth(event.request);
    await readJson(event.request);
    const invite = createInvite(getDb(), auth.user.id);
    return json(
      {
        id: invite.id,
        invite_url: new URL(invite.invite_url_path, event.url.origin).toString(),
        expires_at: invite.expires_at,
      },
      { status: 201 },
    );
  } catch (err) {
    return errorJson(err);
  }
}

