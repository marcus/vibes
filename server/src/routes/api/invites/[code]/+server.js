import { json } from "@sveltejs/kit";
import { getDb } from "$lib/server/db.js";
import { getInviteByCode, getUserPublic, inviteState } from "$lib/server/relay.js";

// Public invite lookup — the code itself is the capability, same contract as
// the /invite/<code> landing page. Powers the app's "<name> invited you"
// sheet. Never reveals more than the landing page already does.
export function GET({ params }) {
  const db = getDb();
  const invite = getInviteByCode(db, params.code);
  if (!invite || inviteState(invite) !== "open") {
    return json({ state: "unusable", inviter: null });
  }
  const inviter = getUserPublic(db, invite.creator_user_id);
  return json({ state: "open", inviter: inviter?.display_name ?? null });
}
