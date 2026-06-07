import { fail } from "@sveltejs/kit";
import { getDb, writeTx } from "$lib/server/db.js";
import { RelayError, createUser } from "$lib/server/relay.js";
import { adminCreateInviteFor } from "$lib/server/admin.js";

/** @type {import('./$types').Actions} */
export const actions = {
  default: async ({ request, url }) => {
    const data = await request.formData();
    const handle = String(data.get("handle") ?? "").trim();
    const displayName = String(data.get("display_name") ?? "").trim();
    const mint = data.get("mint") === "on";

    try {
      // One transaction so a failed invite mint can't leave a half-created user.
      const db = getDb();
      const { user, inviteUrl } = writeTx(db, () => {
        const user = createUser(db, { handle, displayName });
        const inviteUrl = mint
          ? new URL(adminCreateInviteFor(db, user.id).invite_url_path, url.origin).toString()
          : null;
        return { user, inviteUrl };
      });
      return { created: user, inviteUrl };
    } catch (err) {
      if (err instanceof RelayError) {
        return fail(err.status, {
          error: err.message,
          field: err.code,
          handle,
          display_name: displayName,
          mint,
        });
      }
      throw err;
    }
  },
};
