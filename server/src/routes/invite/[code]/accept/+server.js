import { json } from "@sveltejs/kit";
import { getDb } from "$lib/server/db.js";
import { checkRateLimit, errorJson, readJson } from "$lib/server/http.js";
import { acceptInvite } from "$lib/server/relay.js";

function buildConfig(origin, { handle, displayName, deviceLabel }) {
  return {
    identity: { handle, display_name: displayName },
    device: { label: deviceLabel || "Mac" },
    server: { relay_url: origin },
    repos: [],
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

export async function POST(event) {
  try {
    checkRateLimit(event, "invite:accept", 20);
    const body = await readJson(event.request);
    const displayName = body.display_name ?? body.displayName;
    const deviceLabel = body.device_label ?? body.deviceLabel ?? "Mac";
    const { user, token } = acceptInvite(getDb(), event.params.code, {
      handle: body.handle,
      displayName,
      deviceLabel,
    });
    return json(
      {
        token: token.token,
        config: buildConfig(event.url.origin, {
          handle: user.handle,
          displayName: user.display_name,
          deviceLabel,
        }),
      },
      { status: 201 },
    );
  } catch (err) {
    return errorJson(err);
  }
}

