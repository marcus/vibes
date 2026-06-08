import { getDb } from "$lib/server/db.js";
import { getInviteByCode, getUserPublic, inviteState } from "$lib/server/relay.js";

/** @type {import('./$types').PageServerLoad} */
export function load({ params }) {
  const db = getDb();
  const invite = getInviteByCode(db, params.code);
  if (!invite) return { state: "unusable", code: params.code, inviter: null };

  const state = inviteState(invite);
  if (state !== "open") return { state: "unusable", code: params.code, inviter: null };

  const inviter = getUserPublic(db, invite.creator_user_id);
  return { state: "open", code: params.code, inviter: inviter?.display_name ?? null };
}
