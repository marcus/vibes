import { fail, redirect } from "@sveltejs/kit";
import { getDb } from "$lib/server/db.js";
import { checkRateLimit } from "$lib/server/http.js";
import { RelayError } from "$lib/server/relay.js";
import {
  SESSION_COOKIE,
  createSession,
  sessionCookieOptions,
  sweepExpiredSessions,
  verifyAdminPassword,
} from "$lib/server/sessions.js";

/** Only ever redirect back into the admin area; never to an arbitrary URL. */
function safeNext(raw) {
  const next = String(raw ?? "");
  if (next.startsWith("/admin") && !next.startsWith("/admin/login")) return next;
  return "/admin";
}

/** @type {import('./$types').Actions} */
export const actions = {
  default: async (event) => {
    const { request, cookies, url } = event;
    const form = await request.formData();
    const password = String(form.get("password") ?? "");
    const next = safeNext(form.get("next"));

    try {
      // Per-IP limit so the constant-time compare can't be brute-forced.
      checkRateLimit(event, "admin:login", 10);
    } catch (err) {
      if (err instanceof RelayError) {
        return fail(429, { error: "Too many attempts. Try again shortly.", next });
      }
      throw err;
    }

    if (!verifyAdminPassword(password)) {
      return fail(401, { error: "That password is not correct.", next });
    }

    const db = getDb();
    sweepExpiredSessions(db);
    const { token } = createSession(db, { kind: "admin" });
    cookies.set(SESSION_COOKIE, token, sessionCookieOptions(url));

    throw redirect(303, next);
  },
};
