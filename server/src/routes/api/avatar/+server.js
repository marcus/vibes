import { json } from "@sveltejs/kit";
import { getDb } from "$lib/server/db.js";
import { checkRateLimit, errorJson, requireAuth } from "$lib/server/http.js";
import {
  RelayError,
  clearUserAvatar,
  sanitizePng,
  setUserAvatar,
  validatePng,
} from "$lib/server/relay.js";

const MAX_AVATAR_BYTES = 1_500_000;
const MAX_PROMPT_LENGTH = 240;
const MAX_STYLE_LENGTH = 64;

/**
 * Collect a request body as raw bytes with a hard cap, mirroring the streaming
 * pattern in http.js readTextLimited but accumulating Buffers (the body is a
 * binary PNG, not JSON).
 * @param {Request} request
 * @param {number} maxBytes
 * @returns {Promise<Buffer>}
 */
async function readBytesLimited(request, maxBytes) {
  const contentLength = Number(request.headers.get("content-length") ?? 0);
  if (contentLength > maxBytes) {
    throw new RelayError("payload_too_large", "Request body is too large.", 413);
  }
  if (!request.body) return Buffer.alloc(0);
  const reader = request.body.getReader();
  const chunks = [];
  let total = 0;
  while (true) {
    const { value, done } = await reader.read();
    if (done) break;
    total += value.byteLength;
    if (total > maxBytes) {
      throw new RelayError("payload_too_large", "Request body is too large.", 413);
    }
    chunks.push(Buffer.from(value));
  }
  return Buffer.concat(chunks);
}

function headerValue(request, name, maxLength) {
  const raw = request.headers.get(name);
  if (raw == null) return null;
  return String(raw).trim().slice(0, maxLength) || null;
}

export async function POST(event) {
  try {
    checkRateLimit(event, "avatar:post", 10);
    const auth = requireAuth(event.request);
    const bytes = await readBytesLimited(event.request, MAX_AVATAR_BYTES);
    const { width, height } = validatePng(bytes);
    // Re-encode to only the essential chunks, dropping metadata and any bytes an
    // untrusted client appended past IEND before we store/serve the file.
    const clean = sanitizePng(bytes);
    const prompt = headerValue(event.request, "x-avatar-prompt", MAX_PROMPT_LENGTH);
    const style = headerValue(event.request, "x-avatar-style", MAX_STYLE_LENGTH);
    const result = setUserAvatar(getDb(), auth.user, {
      bytes: clean,
      contentType: "image/png",
      width,
      height,
      prompt,
      style,
    });
    return json(result);
  } catch (err) {
    return errorJson(err);
  }
}

export async function DELETE(event) {
  try {
    checkRateLimit(event, "avatar:delete", 10);
    const auth = requireAuth(event.request);
    return json(clearUserAvatar(getDb(), auth.user));
  } catch (err) {
    return errorJson(err);
  }
}
