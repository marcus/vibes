import { getDb } from "$lib/server/db.js";
import { listUsers } from "$lib/server/admin.js";

/** @type {import('./$types').PageServerLoad} */
export function load({ url }) {
  const search = url.searchParams.get("search") ?? "";
  const sort = url.searchParams.get("sort") ?? "handle";
  const users = listUsers(getDb(), { search, sort });
  return { users, search, sort, total: users.length };
}
