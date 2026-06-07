import { error, redirect } from "@sveltejs/kit";
import { getDb } from "$lib/server/db.js";
import {
  SESSION_COOKIE,
  isAdminEnabled,
  resolveSession,
} from "$lib/server/sessions.js";

/**
 * Guard for everything under /admin.
 *
 * - No password configured → the whole area is 404, including the login page,
 *   so an un-configured relay exposes no admin surface.
 * - No live session → redirect to /admin/login (the only unauthenticated route
 *   besides the implicit error page).
 * - Live session already at /admin/login → bounce to the dashboard.
 *
 * @type {import('./$types').LayoutServerLoad}
 */
export function load({ cookies, url }) {
  if (!isAdminEnabled()) {
    throw error(404, "Not found");
  }

  const onLoginPage = url.pathname === "/admin/login";
  const token = cookies.get(SESSION_COOKIE);
  const session = token ? resolveSession(getDb(), token) : null;

  if (!session) {
    if (token) cookies.delete(SESSION_COOKIE, { path: "/admin" });
    if (!onLoginPage) {
      const next = url.pathname + url.search;
      throw redirect(303, `/admin/login?next=${encodeURIComponent(next)}`);
    }
    return { session: null };
  }

  if (onLoginPage) {
    throw redirect(303, "/admin");
  }

  return { session: { kind: session.kind, userId: session.user_id } };
}
