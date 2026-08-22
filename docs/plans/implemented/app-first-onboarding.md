# Vibes: App-First Onboarding & Invite Links

Status: implemented (moved from active 2026-08-21).

## Purpose

Today's signup flow is two-headed and awkward: a person downloads the Mac app, then has to obtain a relay token out-of-band from an admin or by filling out a web form that mints a token and makes them copy it into the app. The web form also creates the user account, so identity is split between "the website made me" and "the app holds my token."

This plan collapses that into a single, app-first model that reads like a normal small Mac app:

1. You download Vibes. On first launch, you enter a display name and the app creates its identity and token through the relay. No website visit, no token to copy.
2. To connect with someone, you tap Add Friend in the app. It produces a one-time invite link.
3. Your friend clicks the link. If they have Vibes, the browser opens the app through `vibes://invite/<code>` and they tap Accept. If they do not have Vibes, the page sends them to the download and shows the invite code to paste once the app is running.

No passwords, no OAuth, no centralized login. The relay stays private and dumb: it mints local-app identities, stores bearer-token hashes, stores one-time invite hashes, and records friendships.

## Goals

- A new user is fully set up by installing the app and entering only a display name. No token handling in the default path.
- The relay derives a unique handle from the display name during registration. The handle is stored in config and can become editable later under Advanced or profile settings.
- Identity and token are created in-app via a self-register API call; the token never leaves the Mac except as a bearer header.
- Add Friend generates a one-time invite link, shareable by any channel.
- Clicking an invite link opens the app for users who have it through the custom `vibes://` URL scheme.
- For users who do not have the app, the web page shows the invite code and the app accepts a pasted code after onboarding.
- Accepting an invite creates a mutual friendship between two existing identities. It no longer creates a user.
- The website homepage explains the new app-first flow while staying minimal.

## Non-Goals (v1)

- Passwords, email, password reset, OAuth, or centralized login.
- Universal Links. Use a custom URL scheme now; `apple-app-site-association`, associated-domains entitlement, and signing wiring can come later.
- In-app friend discovery, search, public profiles, or a friend directory. Connections are link-only.
- Friend requests with a pending/approval state. Accepting a one-time link is the approval.
- Adding friends from the website. Normal users have no web session; admin stays separate.
- Multi-device account linking. A second Mac can still use the Advanced "I already have a token" path.
- Editing display name or handle after first launch. Keep the model compatible with this future feature, but do not build it in this slice.
- A remove-friend UI in the Friends tab. The API already exists; this plan only covers onboarding and invite acceptance.
- Mobile/iOS. macOS only.

## End-to-End Flow

### Install and Register

```
Download Vibes
  -> first launch
  -> enter display name
  -> app calls POST /api/register { display_name, device_label? }
  -> relay derives unique handle, creates user, creates token in one transaction
  -> app stores config on disk and raw token in Keychain
  -> user lands in the main window
```

### Add a Friend

```
Marcus has the app
  -> taps Friends > Create invite link
  -> app calls POST /api/invites with Marcus's bearer token
  -> relay returns https://vibes.opentangle.com/i/<code>
  -> Marcus sends that link by iMessage, email, or Slack

Dana opens the link
  -> web page /i/<code> resolves the invite and shows "Marcus invited you"
  -> if Dana has the app, she clicks Open in Vibes
  -> browser launches vibes://invite/<code>
  -> app shows an accept sheet
  -> app calls POST /api/invites/<code>/accept with Dana's bearer token
  -> relay creates Marcus <-> Dana friendship rows and marks the invite used
  -> both feeds show each other after refresh
```

### No-App Fallback

```
Dana opens /i/<code> without Vibes installed
  -> page offers Download for Mac and shows the invite code
  -> Dana installs and launches Vibes
  -> app asks for display name and self-registers
  -> Dana opens Friends > Have an invite code?
  -> Dana pastes the code and accepts it
  -> same authenticated accept endpoint creates the friendship
```

The key idea that removes the browser-auth problem: the browser never authenticates anyone. It only carries a code and hands it to the app or to the human. The app, which already holds the user's token, is the only client that accepts an invite.

## Accepted Product Decisions

- **Display name only in default onboarding.** The user enters `display_name`; the relay derives a unique `handle`. Do not ask for handle on first launch.
- **Derived handles are server-owned.** Registration must be race-safe and deterministic enough to test. The client displays the returned handle only as account metadata.
- **Short invite links are good for v1.** Use `https://vibes.opentangle.com/i/<code>` for shared links. No custom domain work in this plan.
- **Multi-device is out of scope.** A second Mac can be configured manually through Advanced using an existing token.
- **Used invite revocation does not undo friendship.** Revoking only affects open invites. Do not add remove-friend UI here.
- **Show-the-code fallback is approved.** No clipboard magic and no token baked into the download.

## API Contracts

### `POST /api/register`

New app-facing route: `server/src/routes/api/register/+server.js`.

Request:

```json
{
  "display_name": "Dana",
  "device_label": "Dana MacBook"
}
```

Response `201`:

```json
{
  "user": {
    "id": "uuid",
    "handle": "dana",
    "display_name": "Dana"
  },
  "token": "raw-token-shown-once"
}
```

Rules:

- Rate-limit by IP with `checkRateLimit(event, "register:create", 10)`.
- Accept `display_name` and optional `device_label`. Accept `displayName` and `deviceLabel` aliases only if the existing route style makes that useful for client ergonomics; canonical JSON is snake case.
- Do not accept a user-provided handle in the default contract. If an optional `handle` is kept for a hidden Advanced path, validate it through `createUser`; the UI still must not ask for it by default.
- Create user + token inside one `writeTx`.
- Return the raw token exactly once. Store only the token hash, same as `createToken`.
- Map `RelayError` through `errorJson`.
- Keep `POST /api/users` for admin/CLI bootstrap; it still creates a user without a token.

### `POST /api/invites`

Existing authenticated route, but shared links should now be short.

- Keep `requireAuth(event.request)`.
- Keep creating one-time invite codes through `createInvite`.
- Return `invite_url` using `/i/<code>`, not `/invite/<code>`.
- Update `createInvite` to return `invite_url_path: /i/<code>` or have the route translate the returned code into `/i/<code>`. Prefer changing the helper so admin-created links and app-created links match.
- Existing `/invite/<code>` pages may remain as canonical pages or redirects, but new links should use `/i/<code>`.

### `POST /api/invites/:code/accept`

New authenticated route: `server/src/routes/api/invites/[code]/accept/+server.js`.

- Call `requireAuth(event.request)` to identify the accepting user.
- Call `acceptInvite(getDb(), params.code, { acceptingUserId: auth.user.id })`.
- Return `200 { inviter, friend }`.
- `inviter` is the invite creator public user.
- `friend` is the accepting public user.
- Do not create a user.
- Do not mint a token.
- Do not return config JSON.

Success response:

```json
{
  "inviter": {
    "id": "uuid",
    "handle": "marcus",
    "display_name": "Marcus"
  },
  "friend": {
    "id": "uuid",
    "handle": "dana",
    "display_name": "Dana"
  }
}
```

Error behavior:

- Unknown, expired, revoked, or already-used invite: `410 invite_unusable`.
- Self-accept: `400 invite_self`.
- Missing/invalid token: existing `401 unauthorized`.
- Already friends: return `200` with the same shape, mark the invite accepted, and rely on `INSERT OR IGNORE` to avoid duplicate rows.

## Backend Implementation

All files are under `server/src/` unless noted.

### 1. Add server-side registration

Add helpers in `lib/server/relay.js`:

- `deriveHandleBase(displayName)`:
  - trim and lowercase,
  - normalize diacritics if practical,
  - replace non-`[a-z0-9]` runs with `-`,
  - trim leading/trailing `-` or `_`,
  - fall back to `friend`,
  - reserve room for suffixes and keep final handles at `<= 32` chars.
- `registerUser(db, { displayName, deviceLabel, handle? })`:
  - validate display name by reusing `createUser`,
  - derive candidate handles inside `writeTx`,
  - try `base`, then `base-2`, `base-3`, etc.,
  - create the token in the same transaction,
  - return `{ user, token }`.

Implementation note: because `writeTx` uses an IMMEDIATE transaction, concurrent registrations serialize. Still catch `handle_taken` while trying candidates so the behavior is correct even if helper code is reused elsewhere.

Add route `routes/api/register/+server.js`:

- `checkRateLimit(event, "register:create", 10)`.
- `readJson(event.request)`.
- `displayName = body.display_name ?? body.displayName`.
- `deviceLabel = body.device_label ?? body.deviceLabel ?? "Mac"`.
- `registerUser(getDb(), { displayName, deviceLabel })`.
- Return `201 { user, token: token.token }`.

### 2. Refactor invite acceptance to friendship-only

Change `acceptInvite` in `lib/server/relay.js`.

Old signature:

```js
acceptInvite(db, code, { handle, displayName, deviceLabel })
```

New signature:

```js
acceptInvite(db, code, { acceptingUserId })
```

Inside the existing `writeTx`:

1. Look up invite with `getInviteByCode`.
2. Reject unknown or non-open invite with `RelayError("invite_unusable", ..., 410)`.
3. Reject self-accept if `invite.creator_user_id === acceptingUserId`.
4. Fetch inviter and accepting user through `getUserPublic`; fail with `not_found` if the accepting user no longer exists.
5. Insert both friendship rows using `INSERT OR IGNORE`.
6. Mark the invite accepted with `accepted_by_user_id = acceptingUserId` and `accepted_at = now()`.
7. Return `{ inviter, friend }`.

Do not call `createUser` or `createToken` from this function anymore.

### 3. Add authenticated accept route

Add `routes/api/invites/[code]/accept/+server.js`.

- Mirror the error envelope style used by the other API routes.
- Use `params.code` exactly as supplied; the code is base64url, so no extra path decoding should be needed beyond SvelteKit's normal params.
- Do not read a body. The bearer token decides who accepts.

### 4. Rewrite invite web pages as hand-off pages

Update `routes/invite/[code]/+page.server.js`:

- Keep `load()` resolving invite state and inviter display name.
- Return `{ state, code, inviter }` for open invites.
- Remove `actions`.
- Remove `buildConfig`.
- Remove all token/config generation.

Update `routes/invite/[code]/+page.svelte`:

- Remove `enhance`, form state, token copy, and config download UI.
- For `open`, show:
  - "{inviter} invited you to Vibes."
  - primary link/button to `vibes://invite/<code>` with text "Open in Vibes",
  - secondary link to `/download` with text "Download for Mac",
  - invite code displayed in a selectable code block with a copy button,
  - short instruction: "After installing, paste this code in Friends."
- For unusable/unknown, show a fresh-link message. If inviter is unknown, omit the name.
- Keep the existing minimal visual language. Use no emoji.

Add `/i/[code]`:

- Preferred: `server/src/routes/i/[code]/+server.js` redirects to `/invite/${params.code}` with `307`.
- Alternative: serve the same page at `/i/[code]`; redirect is smaller and avoids duplicate Svelte files.

Delete obsolete public accept route:

- Remove `server/src/routes/invite/[code]/accept/+server.js`.
- Remove any tests or docs that call the old unauthenticated route.

### 5. Preserve admin behavior

Admin and CLI can still create users and tokens manually.

- `POST /api/users` remains unchanged.
- Admin invite creation should return `/i/<code>` once `createInvite` changes.
- Admin user detail pages that build invite URLs from `invite_url_path` should keep working.
- Update seed scripts and admin tests that call `acceptInvite` so they create the accepting user first, then call the new friendship-only accept.

### 6. Data and migrations

No schema change is required.

Existing tables remain valid:

- `users`
- `auth_tokens`
- `friendships`
- `invites`
- `statuses`

Existing users and tokens continue working. Existing open invite codes continue resolving because the code hash lookup is unchanged. Once this ships, an unaccepted old invite no longer creates a new account from the website; it must be accepted by an app identity.

Add a release-note line:

> Token-based setup is still available under Advanced. Invite links now connect two app-created identities instead of creating accounts on the web.

## Client Implementation

All files are under `client/Vibes/`.

### 1. Register the `vibes://` URL scheme

Update `Info.plist` with:

- `CFBundleURLTypes`
- one URL type with `CFBundleURLName = com.marcusvorwaller.vibes.invite`
- `CFBundleURLSchemes = [vibes]`

Update `VibesApp.swift`:

- Add `.onOpenURL { url in model.handleIncomingURL(url) }` to `ContentView()`.
- Bring the app/window forward on URL open using `NSApp.activate(ignoringOtherApps: true)`.
- Keep Sparkle and menu bar wiring unchanged.

### 2. Replace default token setup with self-register

Add client models in `Models.swift` or near `RelayClient`:

- `RegisterRequest`
- `RegisteredIdentity`
- `AcceptInviteResult`

Add `RelayClient.register(displayName:deviceLabel:) async throws -> RegisteredIdentity`:

- `POST /api/register`
- No bearer token required.
- Decode `user.handle`, `user.display_name`, and `token`.

Keep the existing `RelayClient` bearer behavior for authenticated routes. If the current `send` helper always adds `Authorization`, either:

- add a second unauthenticated send helper for register, or
- make auth header optional and only include it when `token` is non-empty.

Update `AppModel.swift`:

- Add `register(displayName:deviceLabel:relayURLText:)`.
- Normalize and validate relay URL with the existing rules.
- Call `RelayClient(baseURL: relayURL, token: "").register(...)`.
- Build `VibesConfig.firstLaunch(relayURL: relayURL, handle: returned.user.handle, displayName: returned.user.displayName, deviceLabel: label)`.
- Save config and token through existing `install(config:token:)`.
- Default relay URL to `https://vibes.opentangle.com`.
- Keep `completeManualSetup` and `importConfigFile`, but move them behind Advanced and update their copy so they are not the default first-launch path.

### 3. Handle incoming invite URLs

Add state to `AppModel.swift`:

- `@Published var pendingInvite: PendingInvite?`
- `@Published var inviteCodeInput: String = ""`
- optional `@Published var successMessage: String?` if the existing footer/error pattern is not enough.

Add:

```swift
func handleIncomingURL(_ url: URL)
func acceptPendingInvite() async
func acceptInvite(code: String) async
```

Parsing rules:

- Accept only scheme `vibes`.
- Accept only host `invite`.
- Read the first non-empty path component as the code.
- Trim whitespace.
- Ignore unknown URLs without showing an error.
- If not configured, store the code and show onboarding; after successful registration, surface the accept sheet.
- If configured, set `pendingInvite` so the sheet appears.

`vibes://invite/abc123` has:

- scheme: `vibes`
- host: `invite`
- path component: `abc123`

Do not parse the host as the code.

Add `RelayClient.acceptInvite(code:) async throws -> AcceptInviteResult`:

- `POST /api/invites/<code>/accept`
- bearer token required.
- Decode `{ inviter, friend }`.

After accept:

- clear pending/input code,
- refresh feed and invites,
- show "Now friends with {inviter.displayName}."

### 4. Add paste-a-code path

In the Friends section, add a compact "Have an invite code?" field and Accept button.

- Reuse `acceptInvite(code:)`.
- Disable Accept for empty/whitespace-only codes.
- Show expired/used/self errors in the same existing error surface.
- Keep the field visually quiet and use existing `Field`, `AccentButtonStyle`, and `PlainVibeButtonStyle`.

### 5. Rename Invites to Friends

Update `ContentView.swift`:

- Change segmented control case from `invites` to `friends`.
- Rename `InvitesSection` to `FriendsSection` or keep the struct name but expose "friends" in the UI. Prefer renaming for agent readability.
- Keep existing create/copy/list/revoke invite wiring.
- Add a native Share button if straightforward with AppKit `NSSharingServicePicker`; otherwise copy link is enough for this implementation pass.

## Mac App UI Requirements

The app window stays fixed at `460 x 620`. Maintain the current warm off-black/off-white palette and restrained accent. Use SF Symbols in buttons where icons are needed. Do not use emoji.

### First-Launch Onboarding

Default UI asks only for display name:

```
vibes
private presence for coding friends

Let's set you up. This stays on your Mac.

display name
[ Marcus                                      ]

[ checkmark icon ] Create my identity

Advanced
  relay url
  I already have a token

error slot
```

Behavior:

- Display name required.
- Device label auto-filled from `Host.current().localizedName ?? "Mac"`.
- Server derives handle and returns it.
- On success, go directly to main panel.
- On error, keep input and show the relay error message.

### Friends Tab

The segmented control becomes `feed`, `repos`, `friends`.

```
vibes                         Marcus     [ Broadcasting ]

[ feed ] [ repos ] [ friends ]                         [ refresh icon ]

Add a friend
Send a one-time link. They tap it and you're connected.

[ link icon ] Create invite link

https://vibes.opentangle.com/i/7Qm3-X2pK
[ copy icon ] Copy link        [ share icon ] Share

Have an invite code?
[ 7Qm3-X2pK                  ] [ Accept ]

Pending invites
open       expires in 7 days          [ Revoke ]
accepted   by dana
```

### Incoming Invite Sheet

Triggered by `vibes://invite/<code>`:

```
You've been invited

Dana wants to share their vibe with you.

[ Accept ] [ Not now ]

Accepting lets you both see each other's presence.
```

If the app does not know the inviter name before accepting, use "Someone invited you to Vibes" and show the code in small muted text. Do not add an unauthenticated "preview invite" API unless needed; the web page already previews the inviter.

On accept success, dismiss the sheet and show "Now friends with Dana" or "Now friends with Marcus" based on the `inviter` returned by the API.

## Website Homepage Changes

Update `server/src/routes/+page.svelte` only in the get-started copy.

Current steps:

```text
1. Download and install Vibes for macOS.
2. Get a relay token from the person running your group.
3. Add the local Git repos you want summarized.
4. Choose Broadcasting, Quiet, or Offline.
```

New steps:

```text
1. Download and install Vibes for macOS.
2. Open it and enter a display name.
3. Tap Add Friend to send a one-time invite link, or accept one you were sent.
4. Add your local repos and choose Broadcasting, Quiet, or Offline.
```

No layout, color, or component changes. The existing Download for Mac CTA stays.

## Tests and Verification

Because this plan changes code across server and client, the implementing agent must satisfy the repo Definition of Done.

### Server tests

Update `server/tests/relay.test.js`:

- `registerUser` creates a user and token in one transaction.
- duplicate display names derive unique handles, e.g. `dana`, `dana-2`.
- invalid/empty display names are rejected.
- `acceptInvite` now requires an existing accepting user.
- accepting creates two friendship rows and marks invite accepted.
- self-accept returns `invite_self`.
- second accept of same invite returns `invite_unusable`.
- accepting when already friends is idempotent and does not duplicate rows.
- raw invite codes and raw tokens are still never stored.

Update `server/tests/admin.test.js` and seed scripts:

- Any call to `acceptInvite(db, code, { handle, displayName })` must become:
  - `const user = createUser(...)`
  - optionally `createToken(...)`
  - `acceptInvite(db, code, { acceptingUserId: user.id })`
- Invite URL path expectations should accept `/i/<code>`.

Add route-level tests if there is already a route-test pattern. If not, helper-level tests plus existing API smoke coverage are acceptable for this pass.

Required server command:

```bash
make server-check
```

### Client verification

Required client command:

```bash
make client
```

Manual app proof:

1. Run the relay locally or against a staging relay.
2. Launch a clean app state with no config/token.
3. Register with a display name only.
4. Confirm config contains returned handle and Keychain contains token.
5. Create a second identity, create an invite from the first, accept from the second.
6. Confirm both feeds show each other.
7. Test `vibes://invite/<code>` opens the app and shows the accept sheet.
8. Test paste-code accept path.

### Full check

If both server and client changed, run:

```bash
make check
```

For UI changes, include a screenshot of the running app or clearly state why screenshot capture was not possible. Passing compile alone is not enough.

## Implementation Order

1. Backend helper changes:
   - add `registerUser` and handle derivation,
   - refactor `acceptInvite`,
   - update tests and seed scripts for new helper signatures.
2. Backend routes:
   - add `/api/register`,
   - add authenticated `/api/invites/[code]/accept`,
   - remove old public `/invite/[code]/accept`,
   - add `/i/[code]` redirect,
   - rewrite invite hand-off page.
3. Client network models:
   - add register and accept invite response/request models,
   - support unauthenticated register call,
   - add authenticated accept invite call.
4. Client app model:
   - implement self-register,
   - implement URL handling and pending invite state,
   - implement paste-code accept.
5. Client UI:
   - replace default setup panel with display-name onboarding,
   - move token setup under Advanced,
   - rename Invites to Friends,
   - add incoming invite sheet.
6. Web copy:
   - update homepage steps.
7. Verification:
   - run relevant checks,
   - test deep link and paste-code flows,
   - capture proof.

## Agent Handoff Checklist

- No default UI asks for a handle.
- `/api/register` returns a user and raw token once.
- User + token registration is atomic.
- Derived handle collisions are handled without asking the user.
- New invite URLs use `/i/<code>`.
- Browser hand-off page never creates users or returns tokens.
- The only invite accept endpoint is authenticated.
- Old token setup remains available under Advanced.
- Existing admin bootstrap paths still work.
- Existing users/tokens remain valid.
- No raw repo paths, branch names, commit messages, filenames, editor activity, process history, or transcripts are added to shared payloads.
- No emoji are introduced in app or web UI.
- `make check` passes when both client and server are touched.
