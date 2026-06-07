import { json } from "@sveltejs/kit";
import { getDb } from "./db.js";
import { RelayError, authenticateToken } from "./relay.js";

const RATE_WINDOW_MS = 60_000;
const buckets = new Map();

function clientIp(event) {
  return (
    event.request.headers.get("x-real-ip")?.trim() ||
    event.request.headers.get("x-forwarded-for")?.split(",").at(-1)?.trim() ||
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

export async function readJson(request, { maxBytes = 64 * 1024 } = {}) {
  const contentLength = Number(request.headers.get("content-length") ?? 0);
  if (contentLength > maxBytes) {
    throw new RelayError("payload_too_large", "Request body is too large.", 413);
  }

  const text = await readTextLimited(request, maxBytes);
  try {
    return JSON.parse(text);
  } catch {
    throw new RelayError("invalid_json", "Request body must be valid JSON.", 400);
  }
}

async function readTextLimited(request, maxBytes) {
  if (!request.body) return "";
  const reader = request.body.getReader();
  const chunks = [];
  let total = 0;
  const decoder = new TextDecoder();

  while (true) {
    const { value, done } = await reader.read();
    if (done) break;
    total += value.byteLength;
    if (total > maxBytes) {
      throw new RelayError("payload_too_large", "Request body is too large.", 413);
    }
    chunks.push(decoder.decode(value, { stream: true }));
  }
  chunks.push(decoder.decode());
  return chunks.join("");
}

export function requireAuth(request) {
  const header = request.headers.get("authorization") ?? "";
  const match = header.match(/^Bearer\s+(.+)$/i);
  return authenticateToken(getDb(), match?.[1]);
}
