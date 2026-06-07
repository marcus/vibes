import { redirect } from "@sveltejs/kit";
import { getDb } from "$lib/server/db.js";
import { getInviteByCode, inviteState } from "$lib/server/relay.js";

/** @type {import('./$types').PageServerLoad} */
export function load({ params }) {
  const db = getDb();
  const invite = getInviteByCode(db, params.code);
  if (!invite) return { state: "unusable", inviter: null };

  const state = inviteState(invite);
  if (state !== "open") return { state: "unusable", inviter: null };

  throw redirect(302, `vibes://invite/${encodeURIComponent(params.code)}`);
}
