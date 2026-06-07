# Vibes: App-First Onboarding & Invite Links

## Purpose

Today's signup flow is two-headed and awkward: a person downloads the Mac app, then has to obtain a *relay token* out-of-band (from an admin, or by filling a web form that mints a token and makes them copy/paste it into the app). The web form even creates the user account, so identity is split between "the website made me" and "the app holds my token."

This plan collapses that into a single, app-first model that reads like a normal consumer app:

1. You download Vibes. On first launch it **creates its own identity and token locally** — no website visit, no token to copy.
2. To connect with someone, you tap **Add Friend** in the app. It produces a **one-time invite link**.
3. Your friend clicks the link. If they have Vibes, the browser **opens the app** (via a `vibes://` URL) and they tap **Accept** — done. If they don't, they download it, and the page shows them the invite **code to paste** once the app is running.

No passwords, no OAuth, no centralized account. The relay stays exactly as private as it is now; we are only changing *how identities are minted and how two existing identities become friends*.

## Goals

- A new user is fully set up by installing the app and choosing a display name. No token handling.
- Identity (user + token) is created in-app via a self-register call; the token never leaves the Mac except as a bearer header.
- "Add Friend" generates a one-time invite link, shareable by any channel (iMessage, email, Slack).
- Clicking an invite link **opens the app** for users who have it (custom `vibes://` URL scheme).
- For users who don't have the app, the post-download page shows the invite **code**, and the app accepts a pasted code.
- Accepting an invite creates a **mutual friendship between two existing identities** — it no longer creates a user.
- The website homepage explains the new three-step flow, staying as minimal as it is today.

## Non-Goals (v1)

- Passwords, email, password reset, OAuth, or any centralized login. (Explicitly rejected.)
- Universal Links (`https://` that open the app directly). We use a custom URL scheme; universal links can come later.
- In-app friend discovery, search, or a friend directory. Connections are link-only.
- Friend requests with a pending/approval state. Accepting a one-time link is the approval.
- Adding friends from the website (no logged-in web session for normal users; admin area is unchanged).
- Mobile/iOS. macOS only.

## The flow

```
                          ┌─────────────────────────────────────────────┐
                          │  INSTALL  (one time, per person)             │
                          └─────────────────────────────────────────────┘

   Download Vibes ──► First launch ──► "Pick a display name + handle"
                                              │
                                              ▼
                              App calls  POST /api/register
                                  { handle, display_name }
                                              │
                              Relay creates user + token (one tx)
                                              │
                              App stores token in Keychain ──► Ready
```

```
                          ┌─────────────────────────────────────────────┐
                          │  ADD A FRIEND                                │
                          └─────────────────────────────────────────────┘

  Marcus (has app)                                  Dana (the invitee)
  ───────────────                                   ──────────────────
  Taps "Add Friend"
      │
      │ POST /api/invites   (Bearer: Marcus)
      ▼
  Relay returns one-time code  ──► link:  https://vibes.../i/<CODE>
      │
      │  sends link by iMessage / email / Slack
      └───────────────────────────────────────────────►  Dana opens link
                                                              │
                                                  ┌───────────┴────────────┐
                                                  │ Web page /i/<CODE>      │
                                                  │ "Marcus invited you."   │
                                                  └───────────┬────────────┘
                                                              │
                            ┌─────────────────────────────────┴───────────────────────────┐
                            ▼                                                               ▼
                 HAS APP  → taps "Open in Vibes"                          NO APP → taps "Download Vibes"
                            │                                                               │
                  Browser launches  vibes://invite/<CODE>                       installs + self-registers
                            │                                                               │
                  App: onOpenURL → confirmation sheet                          page shows the CODE to paste
                  "Become friends with Marcus?"  [Accept]                                   │
                            │                                              In app: "Add Friend ▸ Paste code"
                            ▼                                                               ▼
                  POST /api/invites/<CODE>/accept   (Bearer: Dana) ◄───────────────────────┘
                            │
                  Relay: invite still open?  → create friendship (Marcus ⇄ Dana), mark invite used
                            │
                            ▼
                  Both feeds now show each other. ✔
```

The key idea that removes the "browser can't see local auth" problem: **the browser never authenticates anyone.** It only carries a `<CODE>` and hands it to the app (via deep link) or to the human (via on-page text). The app — which already holds Dana's token — is what calls accept.

## Decisions

- **Identity is created in-app, once, via a new `POST /api/register`.** It mints user + token in a single transaction and returns the raw token once. This replaces manual token entry and the web signup form.
- **Accepting an invite is friendship-only and authenticated.** A new endpoint `POST /api/invites/:code/accept` requires a Bearer token and creates the mutual friendship between the invite's creator and the caller. It never creates a user.
- **Custom URL scheme `vibes://`, not Universal Links.** A `vibes://invite/<CODE>` link opens the app and is handled by SwiftUI `onOpenURL`. This is ~Info.plist + a handler; Universal Links need an `apple-app-site-association` file, the associated-domains entitlement, and signing wiring — deferred.
- **The web invite page becomes a hand-off page, not a signup form.** It shows who invited you and routes you to the app (deep link) or to download + paste-the-code. The user-creating web form and the public token-minting accept path are removed.
- **Self-accept and re-accept are rejected cleanly.** Accepting your own invite, or an expired/used/revoked one, returns a clear error. Accepting an invite from someone already your friend is idempotent (no duplicate rows, friendly message).
- **Handles stay unique and user-chosen.** Self-register surfaces "that handle is taken" so the user can pick another. Display name is free text.
- **Show-the-code is the no-app fallback (approved).** No clipboard magic, no token baked into the download. The page prints the code; the app has a paste field. Reliable and obvious.

## Backend changes (SvelteKit relay)

All in `server/src/`.

### 1. `POST /api/register` — self-serve identity (new)

New route `server/src/routes/api/register/+server.js`.

- Body: `{ handle, display_name, device_label? }`.
- Rate-limited per IP (reuse `checkRateLimit`, e.g. `register:create`, ~10/window — same budget as today's `users:create`).
- Calls a new `relay.js` helper `registerUser(db, { handle, displayName, deviceLabel })` that wraps `createUser` + `createToken` in one `writeTx`.
- Returns `201 { user: { handle, display_name }, token: "<raw>" }`. The raw token is returned exactly once, same contract as `createToken` / `acceptInvite` today.
- `createUser` already validates handle shape/length and throws `handle_taken` (409) on collision — surface that to the client unchanged.

> `POST /api/users` (creates a user, no token) stays for admin/CLI bootstrap. `/api/register` is the app-facing path.

### 2. `acceptInvite` becomes friendship-only

Refactor `server/src/lib/server/relay.js:208`.

- New signature: `acceptInvite(db, code, { acceptingUserId })`.
- Logic inside the existing `writeTx`:
  - Look up invite; reject if not `open` (`invite_unusable`, 410) — unchanged.
  - **Reject self-accept:** if `invite.creator_user_id === acceptingUserId` → `RelayError("invite_self", "You can't accept your own invite.", 400)`.
  - Insert the two `friendships` rows with `INSERT OR IGNORE` (already idempotent today).
  - Mark invite `accepted_by_user_id = acceptingUserId`, `accepted_at = now()`.
  - Return `{ inviter: getUserPublic(creator), friend: getUserPublic(acceptingUserId) }` so the app can say "now friends with Marcus."
- Drop the `createUser` / `createToken` calls from this function — that responsibility moved to `/api/register`.

### 3. `POST /api/invites/:code/accept` — authenticated accept (new)

New route `server/src/routes/api/invites/[code]/accept/+server.js`.

- `requireAuth(event)` → the calling user (Dana).
- Calls `acceptInvite(db, params.code, { acceptingUserId: user.id })`.
- Returns `200 { inviter, friend }` or the mapped `RelayError`.

### 4. Web invite page → hand-off only

Rewrite `server/src/routes/invite/[code]/+page.server.js` and its `+page.svelte`.

- Keep `load()` resolving invite state + inviter display name (already there).
- **Remove** the `actions.default` form that creates a user and shows a token, and remove the `buildConfig` token/JSON download. Identity is no longer created on the web.
- The page (`+page.svelte`) renders, by state:
  - `open`: "**{inviter}** invited you to Vibes." with
    - primary button → `vibes://invite/<CODE>` ("Open in Vibes"),
    - secondary → `/download` ("Don't have Vibes? Download for Mac"),
    - and the **code shown in monospace** with a copy button, labelled "After installing, paste this in the app: `<CODE>`".
  - `unusable`: "This invite has expired or already been used. Ask {inviter} for a new link." (no inviter when the code is unknown).
- Add a short route alias `/i/[code]` that redirects to `/invite/[code]` so links are tweet-short. (Or serve the page directly at `/i/`; redirect is simpler.)
- **Remove** the public user-creating accept route `server/src/routes/invite/[code]/accept/+server.js` (the API twin of the web form). The only accept path now is the authenticated `POST /api/invites/:code/accept`.

### 5. Migration / data

No schema change. `users`, `auth_tokens`, `friendships`, `invites` are unchanged. Existing users and tokens keep working — they already are app-held bearer tokens. Existing open invites created the old way still resolve; they just route through the new hand-off page. (Old invites were single-use account-creating; once we ship, any *unaccepted* old invite will, if clicked by someone with the app, create a friendship instead of an account — acceptable, arguably better. Worth a one-line note at rollout.)

## Client changes (macOS, SwiftUI)

All in `client/Vibes/`.

### 1. Register the `vibes://` URL scheme

- `client/Vibes/Info.plist`: add `CFBundleURLTypes` with a single `CFBundleURLSchemes = ["vibes"]` entry and a `CFBundleURLName` like `com.marcusvorwaller.vibes.invite`.
- `client/Vibes/VibesApp.swift`: add `.onOpenURL { url in model.handleIncomingURL(url) }` to the `WindowGroup` scene. Bring the window to front on open.

### 2. Self-register replaces token entry

- `GitScanner.swift`: add `func register(handle:displayName:deviceLabel:) async throws -> RegisteredIdentity` calling `POST /api/register`, returning `{ handle, displayName, token }`. (Sibling to the existing `createInvite()` at `GitScanner.swift:159`.)
- `AppModel.swift`: add `func register(handle:displayName:deviceLabel:)` that calls the relay, then reuses the existing `install(config:token:)` path (`AppModel.swift:104`) to persist config to disk + token to Keychain. The relay URL defaults to the bundled `https://vibes.opentangle.com` and is hidden behind an "Advanced" disclosure.
- Keep `completeManualSetup` and `importConfigFile` available but demote them to an "Advanced / I already have a token" affordance — useful for re-installs and multi-device, not the default path.

### 3. Handle an incoming invite

- `AppModel.swift`: `func handleIncomingURL(_ url: URL)`:
  - Parse `vibes://invite/<CODE>` (host `invite`, first path component is the code). Ignore anything else.
  - If not yet configured: stash the pending code, run onboarding first, then resume accept.
  - If configured: set `pendingInvite = code` to drive a confirmation sheet.
- `func acceptPendingInvite()` → `GitScanner.acceptInvite(code:)` → `POST /api/invites/<code>/accept`, then refresh the feed and show "Now friends with {inviter}."
- `GitScanner.swift`: add `func acceptInvite(code:) async throws -> AcceptResult` (`POST /api/invites/\(code)/accept`).

### 4. Paste-a-code path (no-app friends)

- In the **Add Friend** section, a small "Have an invite code?" field + Accept button that calls the same `acceptInvite(code:)`. This is what the downloaded-after-clicking friend uses.

## Mac app UI sketches

The app window is fixed `460×620` (`ContentView.swift:14`). Three relevant screens.

### A. First-launch onboarding (replaces `SetupPanel`)

```
┌──────────────────────────────────────────────────────┐
│  vibes                                                 │
│  private presence for coding friends                   │
│                                                        │
│  Let's set you up. This stays on your Mac.             │
│                                                        │
│  display name   ┌──────────────────────────────────┐  │
│                 │ Marcus                           │  │
│                 └──────────────────────────────────┘  │
│  handle         ┌──────────────────────────────────┐  │
│                 │ marcus                           │  │
│                 └──────────────────────────────────┘  │
│                 your friends see this on the feed      │
│                                                        │
│           ┌───────────────────────────┐               │
│           │   ✓  Create my identity    │  ◄ accent     │
│           └───────────────────────────┘               │
│                                                        │
│  ▸ Advanced  (relay url · I already have a token)      │
│                                                        │
│  ⚠ that handle is taken — try another                  │  ◄ error slot
└──────────────────────────────────────────────────────┘
```

"Create my identity" → `POST /api/register` → on success, drops straight into the main panel. Device label is auto-filled from `Host.current().localizedName` (as today) and tucked under Advanced.

### B. Main panel — "Friends" tab with Add Friend (evolves `InvitesSection`)

The segmented control changes from `feed · repos · invites` to `feed · repos · friends`.

```
┌──────────────────────────────────────────────────────┐
│  vibes                    Marcus      [ Broadcasting ▾]│
│                                                        │
│  [ feed ]  [ repos ]  [ friends ]                  ⟳   │
│                                                        │
│  Add a friend                                          │
│  Send a one-time link. They tap it and you're connected.│
│           ┌───────────────────────────┐               │
│           │   🔗  Create invite link   │  ◄ accent     │
│           └───────────────────────────┘               │
│                                                        │
│  ┌──────────────────────────────────────────────────┐ │
│  │ https://vibes.opentangle.com/i/7Qm3-X2pK          │ │ ◄ selectable
│  │            [ Copy link ]   [ Share… ]             │ │
│  └──────────────────────────────────────────────────┘ │
│                                                        │
│  Have an invite code?                                  │
│   ┌─────────────────────────┐  ┌──────────┐           │
│   │ 7Qm3-X2pK               │  │  Accept  │           │
│   └─────────────────────────┘  └──────────┘           │
│                                                        │
│  Pending invites                                       │
│   • open       · expires in 7 days        [ Revoke ]   │
│   • accepted   · by dana                                │
└──────────────────────────────────────────────────────┘
```

Reuses the existing create/copy/list wiring (`createInvite`, `copyLatestInvite`, `invites`, `revokeInvite`). Adds the "Have an invite code?" field and a native Share button.

### C. Incoming invite confirmation (sheet, triggered by `vibes://`)

```
┌──────────────────────────────────────────────────────┐
│                                                        │
│              You've been invited                       │
│                                                        │
│        ┌────────┐                                      │
│        │  D     │   Dana                               │
│        └────────┘   wants to share their vibe with you │
│                                                        │
│      ┌─────────────────┐   ┌─────────────────┐         │
│      │     Accept      │   │     Not now     │         │
│      └─────────────────┘   └─────────────────┘         │
│                                                        │
│  Accepting lets you both see each other's presence.    │
└──────────────────────────────────────────────────────┘
```

"Accept" → `POST /api/invites/<code>/accept` → toast "Now friends with Dana" + feed refresh. Errors (expired/used/self) render in the same sheet with a single "OK."

## Website homepage changes

`server/src/routes/+page.svelte` — keep the current minimal layout and styling; only the "get started" steps change. Today (lines ~38–55):

```
1. Download and install Vibes for macOS.
2. Get a relay token from the person running your group.   ← removed
3. Add the local Git repos you want summarized.
4. Choose Broadcasting, Quiet, or Offline.
```

New steps (still four, no token):

```
1. Download and install Vibes for macOS.
2. Open it and pick a display name — your identity is created on your Mac.
3. Tap "Add Friend" to send a one-time invite link (or accept one you were sent).
4. Add your local repos and choose Broadcasting, Quiet, or Offline.
```

No layout, color, or component changes — just the `<li>` copy. The existing "Download for Mac" CTA stays. (Optional, only if it stays minimal: a one-line "Got an invite link? Click it on the Mac where Vibes is installed." under the steps — leave out unless it reads cleanly.)

## Open questions

1. **Display name only, or handle too?** Self-register needs a unique handle today (DB constraint). Simplest UX: ask for display name, auto-derive a handle (slugify + numeric suffix on collision) and let it be edited under Advanced. Decide before building screen A.
2. **Link length / vanity.** `/i/<code>` keeps it short; do we want a custom domain or is `vibes.opentangle.com/i/...` fine? (Assume fine for v1.)
3. **Multi-device.** A second Mac for the same person currently means a second identity. Out of scope here, but the "I already have a token" Advanced path covers the manual case.
4. **Revoking a used invite** has no effect (already accepted = already friends). Confirm we don't also want a "remove friend" surface in the same screen (it exists in the API: `POST /api/friends/remove`).

## Rollout

1. Backend: `registerUser` + `/api/register`; refactor `acceptInvite`; add `/api/invites/:code/accept`; rewrite invite hand-off page; remove web signup form + public accept route; add `/i/` alias.
2. Client: `vibes://` scheme + `onOpenURL`; `register` flow + onboarding screen A; `handleIncomingURL` + confirmation sheet C; Add Friend screen B with paste-code field.
3. Web: homepage steps copy.
4. Verify end-to-end on two machines (or two identities): install → register → add friend → click link → deep-link accept; and the download-then-paste-code path.
5. Note in release notes that old token-based setup still works via Advanced, and old invite links now create friendships rather than accounts.
```
