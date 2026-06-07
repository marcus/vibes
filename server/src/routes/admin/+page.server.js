import { getDb } from "$lib/server/db.js";
import {
  currentlyBroadcasting,
  dashboardStats,
  listAllInvites,
  recentAudit,
} from "$lib/server/admin.js";

/** @type {import('./$types').PageServerLoad} */
export function load() {
  const db = getDb();
  return {
    stats: dashboardStats(db),
    broadcasting: currentlyBroadcasting(db, 8),
    recentInvites: listAllInvites(db).slice(0, 6),
    audit: recentAudit(db, 6),
  };
}
