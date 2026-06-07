import { fail, redirect } from "@sveltejs/kit";
import { getDb } from "$lib/server/db.js";
import { RelayError } from "$lib/server/relay.js";
import {
  adminCreateInviteFor,
  adminCreateToken,
  adminRemoveFriendship,
  adminRevokeInvite,
  adminRevokeToken,
  deleteUser,
  getUserDetail,
  setUserDisabled,
} from "$lib/server/admin.js";

/** @type {import('./$types').PageServerLoad} */
export function load({ params }) {
  // Unknown id → bounce back to the list; any other error propagates as-is.
  try {
    return { detail: getUserDetail(getDb(), params.id) };
  } catch (err) {
    if (err instanceof RelayError && err.status === 404) throw redirect(303, "/admin/users");
    throw err;
  }
}

/** Run a mutation, translating RelayError into a form failure. */
function guard(fn) {
  try {
    return fn();
  } catch (err) {
    if (err instanceof RelayError) return fail(err.status, { error: err.message });
    throw err;
  }
}

/** @type {import('./$types').Actions} */
export const actions = {
  disable: ({ params }) =>
    guard(() => {
      setUserDisabled(getDb(), params.id, true);
      return { ok: true };
    }),

  enable: ({ params }) =>
    guard(() => {
      setUserDisabled(getDb(), params.id, false);
      return { ok: true };
    }),

  delete: ({ params }) => {
    const result = guard(() => {
      deleteUser(getDb(), params.id);
      return { ok: true };
    });
    if (result?.ok) throw redirect(303, "/admin/users");
    return result;
  },

  mintToken: async ({ params, request }) => {
    const data = await request.formData();
    const label = String(data.get("label") ?? "").trim() || null;
    return guard(() => {
      const token = adminCreateToken(getDb(), params.id, label);
      return { secret: { kind: "token", value: token.token, title: "New bearer token" } };
    });
  },

  revokeToken: async ({ request }) => {
    const data = await request.formData();
    const tokenId = String(data.get("token_id") ?? "");
    return guard(() => {
      adminRevokeToken(getDb(), tokenId);
      return { ok: true };
    });
  },

  createInvite: ({ params, url }) =>
    guard(() => {
      const invite = adminCreateInviteFor(getDb(), params.id);
      const inviteUrl = new URL(invite.invite_url_path, url.origin).toString();
      return { secret: { kind: "link", value: inviteUrl, title: "Invite link" } };
    }),

  revokeInvite: async ({ request }) => {
    const data = await request.formData();
    const inviteId = String(data.get("invite_id") ?? "");
    return guard(() => {
      adminRevokeInvite(getDb(), inviteId);
      return { ok: true };
    });
  },

  removeFriend: async ({ params, request }) => {
    const data = await request.formData();
    const friendId = String(data.get("friend_id") ?? "");
    return guard(() => {
      adminRemoveFriendship(getDb(), params.id, friendId);
      return { ok: true };
    });
  },
};
