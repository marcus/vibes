# AI-Generated Profile Icons (Apple Intelligence)

## Context

Vibes friend cards currently show only a presence dot and a name — no avatar
(`client/Vibes/FriendCard.swift` `header`). We want users to generate a personal
profile icon from a short prompt, with a consistent "house style" applied, using
**Apple Intelligence on-device image generation**. The generated PNG is uploaded
to the relay, stored as a publicly-addressable asset under a short slug, recorded
in the database, and surfaced back to every client via the feed so friends see
each other's icons.

Two hard constraints shape the design:

1. **Generation must happen in the Swift client.** Apple's `ImageCreator`
   (`ImagePlayground` framework) runs models **on device only** — it cannot run
   on the Linux VPS that hosts the Node/SvelteKit relay. The server only stores
   and serves bytes.
2. **Storage must be swappable.** Today: filesystem on the VPS, served by nginx.
   Later: S3/R2. We isolate this behind a small storage-adapter interface chosen
   by env var.

Confirmed decisions: house-style template **served from the server** (tunable
without an app release); **`avatars` table + `users.avatar_id` pointer**;
filesystem assets **served by an nginx alias outside the deployed `server/` tree**
(mirrors the existing `/downloads/` pattern).

---

## Apple Intelligence research summary

Framework: **`ImagePlayground`** (`import ImagePlayground`), the programmatic
`ImageCreator` API. Generation is on-device, free, no model hosting required.

- **Availability:** Apple-Intelligence-capable device, macOS 15.4+. We target
  "latest macOS" so the API is present; we still **must** check at runtime and
  degrade gracefully — not every Mac is AI-capable and models may still be
  downloading.
- **Init:** `let creator = try await ImageCreator()` — throws
  (`ImageCreator.Error.notSupported` / `.unavailable`) when unusable. Treat a
  thrown init as "feature unavailable".
- **Capability probe:** check `creator.availableStyles` (non-empty) and pick our
  preferred style from what's actually available, falling back in priority order.
- **Concepts:** `ImagePlaygroundConcept.text(_:)` for the prompt;
  `.extracted(from:title:)`, `.image(_:)`, `.drawing(_:)` also exist (we use
  `.text`).
- **Generate:**
  ```swift
  let stream = creator.images(for: [.text(fullPrompt)], style: chosenStyle, limit: 1)
  for try await created in stream { let cg: CGImage = created.cgImage; break }
  ```
- **Styles:** Apple-provided `.animation` (3D), `.illustration` (flat 2D),
  `.sketch`; newer OS versions add ChatGPT-backed styles (oil painting,
  watercolor, vector, anime, print). **Always select from `availableStyles`** —
  do not hardcode a single style enum case as guaranteed present.
- **Errors to handle:** `notSupported`, `unavailable`, `creationCancelled`,
  `faceInImageTooSmall`, `unsupportedLanguage`, `unsupportedInputImage`,
  `backgroundCreationForbidden`, `creationFailed`. Map all to a single
  user-facing "couldn't generate — try a different prompt / try later" state.
- **Safety/moderation:** Apple applies on-device content safety during
  generation, so we don't need our own image classifier; the server still
  re-encodes uploads (strip metadata) and enforces size/dimension limits.

Sources:
- [ImageCreator — Apple Developer](https://developer.apple.com/documentation/ImagePlayground/ImageCreator)
- [ImagePlaygroundStyle — Apple Developer](https://developer.apple.com/documentation/ImagePlayground/ImagePlaygroundStyle)
- [images(for:style:limit:)](https://developer.apple.com/documentation/imageplayground/imagecreator/images(for:style:limit:))
- [Generating images programmatically with Image Playground (createwithswift)](https://www.createwithswift.com/generating-images-programmatically-with-image-playground/)
- [Apple Intelligence — Get Started](https://developer.apple.com/apple-intelligence/get-started/)

---

## End-to-end flow

1. Client fetches house-style config (prompt prefix/suffix + preferred style
   order) from the server; caches it.
2. User opens "Profile Icon" in Settings, types a short prompt
   (e.g. "a sleepy fox with headphones").
3. Client composes `housePrefix + userPrompt + houseSuffix`, runs `ImageCreator`
   on-device, renders the first `CGImage` to a square PNG (downscaled to 512×512).
4. User previews; on "Use this", client `POST`s the PNG bytes to the relay.
5. Server validates + re-encodes, asks the **storage adapter** to `put` the bytes
   under a freshly minted **short id**, inserts an `avatars` row, points
   `users.avatar_id` at it, returns the public URL.
6. `/api/me` and `/api/feed` now include `avatar_url`; all clients render it with
   `AsyncImage` (URLCache handles caching). Regeneration mints a new short id
   (old asset becomes immutable history), so URLs are safely cache-`immutable`.

---

## Server changes (SvelteKit / Node / SQLite)

### 1. DB migration v4 — `server/src/lib/server/db.js`

Append (never edit existing migrations) to the `MIGRATIONS` array:

```js
{
  version: 4,
  name: "avatars",
  sql: `
    CREATE TABLE avatars (
      id TEXT PRIMARY KEY,              -- short public slug, also the asset filename stem
      user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      store TEXT NOT NULL,              -- adapter that holds the bytes: 'filesystem' | 's3'
      content_type TEXT NOT NULL,       -- 'image/png'
      width INTEGER NOT NULL,
      height INTEGER NOT NULL,
      byte_size INTEGER NOT NULL,
      prompt TEXT,                      -- user's short prompt (for history/regeneration)
      style TEXT,                       -- ImagePlayground style used
      created_at TEXT NOT NULL
    );
    CREATE INDEX idx_avatars_user_id ON avatars(user_id);
    ALTER TABLE users ADD COLUMN avatar_id TEXT REFERENCES avatars(id);
  `,
}
```

Rationale: the public slug (`avatars.id`) is decoupled from the user UUID, so the
URL never leaks identity and regeneration just mints a new row. `users.avatar_id`
is the "current" pointer. `store` lets a future migration to S3 know where old
assets physically live.

### 2. Short-id helper — `server/src/lib/server/relay.js`

Reuse the existing crypto style (`randomBytes` already imported). Add:

```js
// ~12-char url-safe slug from random bytes; retried on the rare PK collision.
export function newShortId(db, bytes = 9) {
  for (let i = 0; i < 5; i++) {
    const id = randomBytes(bytes).toString("base64url"); // 12 chars, no padding
    const hit = db.prepare("SELECT 1 FROM avatars WHERE id = ?").get(id);
    if (!hit) return id;
  }
  throw new RelayError("internal", "Could not allocate avatar id.", 500);
}
```

### 3. Storage adapter — new `server/src/lib/server/avatarStore.js`

Small interface, selected by env at module load (mirrors how `db.js` reads
`VIBES_DB_PATH`):

```js
// interface: put(id, bytes, contentType) -> void ; remove(id) -> void ; urlFor(id, contentType) -> string ; kind -> string
```

- **FilesystemAvatarStore** — writes `${VIBES_AVATAR_DIR}/<id>.png`
  (`mkdirSync(recursive)` like `openDb`), `urlFor` returns
  `${VIBES_AVATAR_BASE_URL}/<id>.png`.
- **S3AvatarStore** — stub now (throws "not configured"), wired later with the
  S3/R2 SDK; same `put`/`remove`/`urlFor` signature, `urlFor` uses the bucket's
  public/CDN base.
- `getAvatarStore()` singleton picks impl from `VIBES_AVATAR_STORE`
  (`'filesystem'` default).

New env vars (document in `.env.deploy.example`):

| var | meaning | default |
|---|---|---|
| `VIBES_AVATAR_STORE` | `filesystem` \| `s3` | `filesystem` |
| `VIBES_AVATAR_DIR` | on-disk dir for filesystem store | `${DEPLOY_PATH}/avatars` |
| `VIBES_AVATAR_BASE_URL` | public URL prefix the slug is appended to | `https://${DEPLOY_DOMAIN}/avatars` |
| (later) `VIBES_S3_*` | bucket/region/keys/public base for R2/S3 | — |

### 4. House-style config + relay functions — `relay.js`

- `HOUSE_STYLE` constant (server-owned, tunable here):
  ```js
  export const HOUSE_STYLE = {
    prompt_prefix: "A friendly minimalist avatar of ",
    prompt_suffix: ", centered, simple solid background, soft palette",
    styles: ["illustration", "animation", "sketch"], // client picks first available
    image_size: 512,
  };
  ```
- `setUserAvatar(db, user, { bytes, contentType, width, height, prompt, style })`
  — wrapped in `writeTx`: mint `newShortId`, `store.put(...)`, INSERT `avatars`,
  UPDATE `users.avatar_id`, return `{ id, avatar_url }`. (Old asset rows are kept
  as history; no delete on regenerate.)
- Add `avatar_url` to the user-shaping helpers so it flows everywhere:
  `feedUser`, `publicUser`, `registeredUser`, and the `/api/me` payload. Helper:
  `avatarUrlFor(db, user)` → `user.avatar_id ? store.urlFor(...) : null`.
  (`getFeed` already selects friend rows in `relay.js` ~L681 — add `avatar_id`
  to those SELECTs.)

### 5. New routes

- `POST /api/avatar` — new `server/src/routes/api/avatar/+server.js`. Auth via
  `requireAuth`; `checkRateLimit(event, "avatar:post", 10)`; read **raw bytes**
  (not `readJson`) with a ~1.5 MB cap; sniff PNG magic bytes + decode
  dimensions; **re-encode** to strip metadata (use `sharp` if added, otherwise a
  minimal PNG validator + pass-through); call `setUserAvatar`; return
  `{ id, avatar_url }`. Send the short prompt/style as headers or query params
  (e.g. `X-Avatar-Prompt`, `X-Avatar-Style`) since the body is binary.
- `GET /api/avatar/style` (or fold into `/api/me`) — returns `HOUSE_STYLE` so the
  client can render and inject it. Folding into `/api/me` avoids a new round trip;
  a dedicated endpoint keeps `/api/me` lean. **Recommend adding a `house_style`
  block to `/api/me`.**
- Optionally `DELETE /api/avatar` to clear `users.avatar_id` (revert to initials).

### 6. nginx — `deploy/nginx.conf.template`

Add a block alongside `location /downloads/`, pointing **outside** the deployed
`server/` tree so relay redeploys never touch user assets (same reasoning as the
`releases/` comment already in the file):

```nginx
location /avatars/ {
    alias ${DEPLOY_PATH}/avatars/;
    autoindex off;
    types { image/png png; }
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Cache-Control "public, max-age=31536000, immutable";
}
```

`client_max_body_size` is currently `2m` — fine for 512px PNGs. The deploy script
(`scripts/deploy-server.sh`) should `mkdir -p ${DEPLOY_PATH}/avatars` on first
deploy.

---

## Client changes (SwiftUI / macOS)

### 1. Generation engine — new `client/Vibes/AvatarGenerator.swift`

```swift
import ImagePlayground   // gated to macOS 15.4+

enum AvatarGenerationError: Error { case unavailable, failed, cancelled }

@available(macOS 15.4, *)
struct AvatarGenerator {
  static var isSupported: Bool { /* ImageCreator availability probe */ }
  // Composes house prefix/suffix + prompt, runs ImageCreator(limit:1),
  // takes first CGImage, downscales to size×size, returns PNG Data.
  func generate(prompt: String, house: HouseStyle) async throws -> Data
}
```

- Probe support before showing the feature; if `ImageCreator()` throws or
  `availableStyles` is empty → show an explanatory disabled state, never a crash.
- Pick `style` = first of `house.styles` present in `creator.availableStyles`,
  else first available.
- Render `CGImage` → square crop/scale → PNG via `NSBitmapImageRep`.

### 2. Models — `client/Vibes/Models.swift`

- Add `var avatarUrl: String?` (`case avatarUrl = "avatar_url"`) to `UserSummary`.
  This automatically flows into `MergedStatus.user`, `FeedResponse`, `/api/me`.
- Add a `HouseStyle` Codable (`prompt_prefix`, `prompt_suffix`, `styles`,
  `image_size`) and include it in `AccountResponse` (the `/api/me` shape).

### 3. Networking — `client/Vibes/GitScanner.swift` (`RelayClient`)

- `func uploadAvatar(pngData: Data, prompt: String, style: String) async throws -> AvatarUploadResult`
  — a binary POST to `/api/avatar` (set `Content-Type: image/png`, prompt/style
  headers, bearer auth). The existing generic `send<>` is JSON-only, so add a
  small sibling that posts raw `Data`.
- `me()` already exists — it will now also carry `house_style` + `avatar_url`.

### 4. UI

- **Settings → Profile Icon** (the native Settings scene from the in-flight
  `native-settings-and-friend-invite-ui.md` plan, or the current settings sheet):
  prompt text field, "Generate" button, preview, "Use this" / "Regenerate" /
  "Remove". Show progress + the unavailable state when `AvatarGenerator` isn't
  supported.
- **FriendCard** (`client/Vibes/FriendCard.swift` `header`): replace the bare
  presence dot with an avatar: `AsyncImage(url: status.user.avatarUrl)` clipped to
  a `Circle`, with the presence dot as a small overlay badge; fall back to
  initials (first letters of `displayName`) when `avatarUrl` is nil or load
  fails. Keep `VibeColor` tokens and existing sizing (`size.dotSize`).

---

## Why client-generate + server-store (not server-generate)

Apple Intelligence has no server-side API and cannot run on Linux. The client is
the only place the model exists. The server stays a thin relay (consistent with
the repo's "intentionally minimal centralized relay" framing): it validates,
stores via the adapter, and serves. Centralizing only the **house-style template**
on the server gives art-direction control without coupling the relay to Apple
frameworks.

---

## Verification

**Server (no Apple HW needed):**
- Unit-test migration v4 against `:memory:` (`openDb(":memory:")`), assert
  `avatars` table + `users.avatar_id` exist and v4 is recorded in
  `schema_migrations`.
- Test `newShortId` uniqueness/retry and `FilesystemAvatarStore.put/urlFor`
  against a temp dir.
- `curl -X POST $RELAY/api/avatar -H "Authorization: Bearer $TOK" -H "Content-Type: image/png" --data-binary @sample.png`
  → expect `{ id, avatar_url }`; `GET /api/me` and `/api/feed` now include
  `avatar_url`; `GET $avatar_url` returns the PNG (locally via the SvelteKit
  static dir / on the VPS via nginx).

**Client (on an Apple-Intelligence Mac, latest macOS):**
- Build, open Settings → Profile Icon, generate from a prompt, confirm preview,
  upload, and that your own FriendCard + a friend's card render the icon.
- Test the unavailable path on a non-AI Mac (or by forcing the probe false):
  feature shows a disabled explanation, no crash; cards fall back to initials.

**Storage swap:**
- Set `VIBES_AVATAR_STORE=filesystem` + `VIBES_AVATAR_DIR=/tmp/avatars` locally;
  confirm files land and `urlFor` matches `VIBES_AVATAR_BASE_URL`. The `s3`
  branch is a stub until R2/S3 credentials are added.

---

## Out of scope / follow-ups

- Real S3/R2 adapter implementation + credential management (interface is built
  now; impl deferred).
- Pruning old avatar history rows/assets (kept as immutable history for now).
- Image-from-image (`.image`/`.drawing` concepts) or user upload of a custom
  (non-AI) avatar.
- Per-friend avatar moderation/reporting (relying on Apple's on-device safety +
  server re-encode for v1).
