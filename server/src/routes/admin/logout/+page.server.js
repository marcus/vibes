import { redirect } from "@sveltejs/kit";
import { getDb } from "$lib/server/db.js";
import { SESSION_COOKIE, deleteSession } from "$lib/server/sessions.js";

/** GET /admin/logout has nothing to render; send people back to the dashboard. */
export function load() {
  throw redirect(303, "/admin");
}

/** @type {import('./$types').Actions} */
export const actions = {
  default: async ({ cookies }) => {
    const token = cookies.get(SESSION_COOKIE);
    deleteSession(getDb(), token);
    cookies.delete(SESSION_COOKIE, { path: "/admin" });
    throw redirect(303, "/admin/login");
  },
};
