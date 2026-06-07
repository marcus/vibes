import { afterEach, beforeAll, describe, expect, it } from "vitest";

// Use an in-memory DB for the singleton getDb() the guard relies on.
process.env.VIBES_DB_PATH = ":memory:";

import { load } from "../src/routes/admin/+layout.server.js";
import { getDb } from "../src/lib/server/db.js";
import { createSession } from "../src/lib/server/sessions.js";

const ORIGINAL = process.env.VIBES_ADMIN_PASSWORD;

afterEach(() => {
  if (ORIGINAL === undefined) delete process.env.VIBES_ADMIN_PASSWORD;
  else process.env.VIBES_ADMIN_PASSWORD = ORIGINAL;
});

/** Run the load and capture whatever it throws (redirect/error) or returns. */
function run({ pathname = "/admin", token = undefined } = {}) {
  const cookies = {
    get: () => token,
    delete: () => {},
  };
  const url = new URL(`http://localhost${pathname}`);
  try {
    return { value: load({ cookies, url }) };
  } catch (thrown) {
    return { thrown };
  }
}

describe("admin route guard", () => {
  it("404s the whole area when no password is configured", () => {
    delete process.env.VIBES_ADMIN_PASSWORD;
    const { thrown } = run({ pathname: "/admin" });
    expect(thrown?.status).toBe(404);

    // Even the login page is hidden.
    expect(run({ pathname: "/admin/login" }).thrown?.status).toBe(404);
  });

  it("redirects unauthenticated requests to the login page", () => {
    process.env.VIBES_ADMIN_PASSWORD = "secret";
    const { thrown } = run({ pathname: "/admin/users" });
    expect(thrown?.status).toBe(303);
    expect(thrown?.location).toContain("/admin/login");
    expect(thrown?.location).toContain("next=");
  });

  it("allows the login page through unauthenticated", () => {
    process.env.VIBES_ADMIN_PASSWORD = "secret";
    const { value, thrown } = run({ pathname: "/admin/login" });
    expect(thrown).toBeUndefined();
    expect(value).toEqual({ session: null });
  });

  it("admits a valid session and exposes its kind", () => {
    process.env.VIBES_ADMIN_PASSWORD = "secret";
    const { token } = createSession(getDb(), { kind: "admin" });
    const { value, thrown } = run({ pathname: "/admin", token });
    expect(thrown).toBeUndefined();
    expect(value.session.kind).toBe("admin");
  });

  it("bounces an authenticated user away from the login page", () => {
    process.env.VIBES_ADMIN_PASSWORD = "secret";
    const { token } = createSession(getDb(), { kind: "admin" });
    const { thrown } = run({ pathname: "/admin/login", token });
    expect(thrown?.status).toBe(303);
    expect(thrown?.location).toBe("/admin");
  });
});
