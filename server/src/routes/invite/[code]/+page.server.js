import { fail } from "@sveltejs/kit";
import { getDb } from "$lib/server/db.js";
import {
  RelayError,
  acceptInvite,
  getInviteByCode,
  getUserPublic,
  inviteState,
} from "$lib/server/relay.js";

/** @type {import('./$types').PageServerLoad} */
export function load({ params }) {
  const db = getDb();
  const invite = getInviteByCode(db, params.code);
  if (!invite) return { state: "unusable", inviter: null };

  const state = inviteState(invite);
  if (state !== "open") return { state: "unusable", inviter: null };

  const inviter = getUserPublic(db, invite.creator_user_id);
  return { state: "open", inviter: inviter?.display_name ?? null };
}

/** Default first-launch config the friend downloads. Never includes the token. */
function buildConfig(origin, { handle, displayName, deviceLabel }) {
  return {
    identity: { handle, display_name: displayName },
    device: { label: deviceLabel || "Mac" },
    server: { relay_url: origin },
    sharing: {
      cards: {
        git_stats: true,
        agent_mix: true,
        repo_aliases: true,
        spotify: false,
        weather: false,
        harness: false,
      },
      redactions: {
        commit_messages: true,
        branch_names: true,
        file_names: true,
        repo_paths: true,
      },
    },
  };
}

/** @type {import('./$types').Actions} */
export const actions = {
  default: async ({ request, params, url }) => {
    const form = await request.formData();
    const handle = String(form.get("handle") ?? "").trim();
    const displayName = String(form.get("display_name") ?? "").trim();
    const deviceLabel = String(form.get("device_label") ?? "").trim().slice(0, 64);

    if (!handle || !displayName) {
      return fail(400, {
        error: "Handle and display name are required.",
        handle,
        display_name: displayName,
        device_label: deviceLabel,
      });
    }

    try {
      const { token } = acceptInvite(getDb(), params.code, {
        handle,
        displayName,
        deviceLabel,
      });
      const config = buildConfig(url.origin, { handle, displayName, deviceLabel });
      // Return only the raw token string, shown once; never the token id/object.
      return { accepted: true, handle, token: token.token, config: JSON.stringify(config, null, 2) };
    } catch (err) {
      if (err instanceof RelayError) {
        return fail(err.status, {
          error: err.message,
          handle,
          display_name: displayName,
          device_label: deviceLabel,
        });
      }
      throw err;
    }
  },
};
