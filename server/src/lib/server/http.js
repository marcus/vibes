import { json } from "@sveltejs/kit";
import { getDb } from "./db.js";
import { RelayError, authenticateToken } from "./relay.js";

const RATE_WINDOW_MS = 60_000;
const buckets = new Map();

function clientIp(event) {
  return (
    event.request.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ||
    event.getClientAddress?.() ||
    "unknown"
  );
}

export function checkRateLimit(event, name, limit = 60) {
  const key = `${name}:${clientIp(event)}`;
  const now = Date.now();
  const bucket = buckets.get(key);
  if (!bucket || bucket.resetAt <= now) {
    buckets.set(key, { count: 1, resetAt: now + RATE_WINDOW_MS });
    return;
  }
  bucket.count += 1;
  if (bucket.count > limit) {
    throw new RelayError("rate_limited", "Too many requests. Try again shortly.", 429);
  }
}

export function errorJson(error) {
  if (error instanceof RelayError) {
    return json(
      { error: { code: error.code, message: error.message } },
      { status: error.status },
    );
  }
  throw error;
}

export async function readJson(request) {
  try {
    return await request.json();
  } catch {
    throw new RelayError("invalid_json", "Request body must be valid JSON.", 400);
  }
}

export function requireAuth(request) {
  const header = request.headers.get("authorization") ?? "";
  const match = header.match(/^Bearer\s+(.+)$/i);
  return authenticateToken(getDb(), match?.[1]);
}

