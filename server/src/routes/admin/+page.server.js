import { getDb } from "$lib/server/db.js";
import {
  currentlyOnline,
  dashboardStats,
  listAllInvites,
  recentAudit,
} from "$lib/server/admin.js";

/** @type {import('./$types').PageServerLoad} */
export function load() {
  const db = getDb();
  return {
    stats: dashboardStats(db),
    online: currentlyOnline(db, 8),
    recentInvites: listAllInvites(db).slice(0, 6),
    audit: recentAudit(db, 6),
  };
}
