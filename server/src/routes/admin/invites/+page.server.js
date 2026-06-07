import { fail } from "@sveltejs/kit";
import { getDb } from "$lib/server/db.js";
import { RelayError } from "$lib/server/relay.js";
import {
  adminCreateInviteFor,
  adminRevokeInvite,
  listAllInvites,
} from "$lib/server/admin.js";

const STATES = ["open", "accepted", "expired", "revoked"];

/** @type {import('./$types').PageServerLoad} */
export function load({ url }) {
  const db = getDb();
  const state = url.searchParams.get("state") ?? "all";

  const all = listAllInvites(db);
  const counts = { all: all.length };
  for (const s of STATES) counts[s] = 0;
  for (const invite of all) counts[invite.state] += 1;

  const invites = state === "all" ? all : all.filter((i) => i.state === state);

  const creators = db
    .prepare("SELECT id, handle, display_name FROM users WHERE disabled_at IS NULL ORDER BY handle ASC")
    .all();

  return { invites, counts, state, creators };
}

/** @type {import('./$types').Actions} */
export const actions = {
  create: async ({ request, url }) => {
    const data = await request.formData();
    const creatorId = String(data.get("creator_id") ?? "");
    if (!creatorId) return fail(400, { error: "Pick a user to create the invite for." });
    try {
      const invite = adminCreateInviteFor(getDb(), creatorId);
      const inviteUrl = new URL(invite.invite_url_path, url.origin).toString();
      return { secret: { kind: "link", value: inviteUrl, title: "Invite link" } };
    } catch (err) {
      if (err instanceof RelayError) return fail(err.status, { error: err.message });
      throw err;
    }
  },

  revoke: async ({ request }) => {
    const data = await request.formData();
    const inviteId = String(data.get("invite_id") ?? "");
    try {
      adminRevokeInvite(getDb(), inviteId);
      return { ok: true };
    } catch (err) {
      if (err instanceof RelayError) return fail(err.status, { error: err.message });
      throw err;
    }
  },
};
