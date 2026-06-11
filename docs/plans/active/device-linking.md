# Device Linking ("Link this Mac")

Single user, multiple Macs: three cooperating paths for connecting a new Mac
to an existing account, plus device management. Replaces the manual-token path
(kept as an Advanced escape hatch) as the supported way to add a device.

## The three paths, fastest first

1. **iCloud Keychain welcome-back (zero effort).** Every signed-in Mac keeps a
   synchronizable Keychain item (`com.marcusvorwaller.vibes.account`) fresh
   with relay URL, identity, and its bearer token — written only **after** a
   sync proves the token works, so a revoked Mac can't advertise a dead
   credential (on a 401 it also deletes the item if it holds its own token).
   A new Mac on the same Apple ID finds the item (checked at launch and on
   every app-activate while unconfigured, since iCloud sync can lag) and the
   setup screen offers "Use this Mac as @handle" — one click calls
   `POST /api/tokens` with the synced credential to mint this Mac its **own
   fresh per-device token**; the synced token is never stored as the working
   credential. A stale synced token gets a 401, the dead item is deleted, and
   the UI falls back to path 2.
2. **Pairing code.** Old Mac: Settings → General → Link Another Mac →
   Generate Code (`POST /api/devices/link-codes`) → short code like
   `8MKW-5XAV` (10-minute expiry, single use). New Mac: setup screen →
   "Already using Vibes on another Mac?" → enter code →
   `POST /api/devices/link-codes/claim` mints a fresh labeled token.
   "Copy Link" yields `vibes://link/<code>?relay=…`, which prefills both the
   code and the relay on an unconfigured Mac (self-hosted relays included).
3. **Manual token / config import** (Advanced, unchanged).

Every path ends in the shared registration install: new local `device_id`,
fresh per-device token in the local Keychain, statuses merging across devices
via the existing `(user_id, device_id)` aggregation.

## Device management

Settings → General → Devices lists the account's active tokens
(`GET /api/devices`): label, created/last-used, with the caller flagged
`current` ("This Mac", not removable from itself). Remove calls the existing
`POST /api/tokens/revoke`; the revoked Mac starts getting 401s on its next
sync.

## Server

- Migration v7: `device_link_codes` (id, code_hash UNIQUE, user_id,
  created_at, expires_at, claimed_at, claimed_device_label). Only hashes are
  stored, same posture as invites.
- Codes: 8 chars from a no-lookalike alphabet (`A-Z` minus I/L/O, `2-9`),
  ~39 bits; claimed case-insensitively, dashes/spaces ignored. Safety =
  single use × 10-minute TTL × claim rate limit (10/min/IP, covered by a
  test). `claimDeviceLinkCode` runs in an IMMEDIATE transaction (single-use
  under concurrency, like `acceptInvite`). Error code `link_code_unusable`
  (410) is uniform across unknown/expired/claimed/disabled — no oracle.
  Expired unclaimed codes are purged on the next create; claimed rows are
  kept as the audit trail of which devices joined.
- Relay functions: `createDeviceLinkCode`, `claimDeviceLinkCode`,
  `listTokens`, `mintDeviceToken` (`src/lib/server/relay.js`).
- Routes: `POST /api/devices/link-codes` (auth),
  `POST /api/devices/link-codes/claim` (unauthenticated — the code is the
  credential), `GET /api/devices` (auth), `POST /api/tokens` (auth, mints a
  labeled token; sibling of `/api/tokens/revoke`).
- Mint/claim/register all return the same `{ user, token }` shape, so the
  client has one decode + install path.

## Client

- `RelayClient`: `createDeviceLinkCode`, `claimDeviceLinkCode`, `listDevices`,
  `mintDeviceToken`, `revokeToken`.
- `AppModel`: `linkThisMac`, `continueAsSyncedAccount`, `createDeviceLinkCode`,
  `refreshDevices`, `revokeDevice`, `refreshSyncedAccountItem` (called on
  launch and install).
- `SyncedAccountStore` (ConfigStore.swift): synchronizable generic-password
  item; all operations best-effort — iCloud Keychain off, or dev builds that
  can't access synchronizable items, degrade silently to the other paths.
- UI: SetupPanel welcome-back card + link-code section (ContentView.swift),
  General settings Devices + Link Another Mac sections.

## Known limits / later

- A revoked Mac sees a clear footer message ("This Mac's access was removed…")
  and stops advertising to iCloud, but there's no dedicated signed-out state
  that clears local config.
- **Ship gate RESOLVED 2026-06-11.** Probe measurements: Developer ID +
  hardened runtime with no entitlements → `errSecMissingEntitlement (-34018)`;
  `keychain-access-groups` without a profile → killed by AMFI (exit 137);
  with an embedded Developer ID provisioning profile + entitlements →
  **errSecSuccess** on add/read/delete of synchronizable items. Wired in:
  `client/Vibes/Vibes.entitlements` (Release config only — debug builds stay
  entitlement-free and degrade silently with OSStatus logging), the
  "Vibes Developer ID" profile at `client/signing/` (expires 2027-02-01,
  contains the team's signing cert serial 16F3FDF7AC516137; regenerate in
  the portal if the cert rotates), `release-mac.sh` installs the profile and
  passes `PROVISIONING_PROFILE_SPECIFIER`, and `ExportOptions.plist` embeds
  it at export. Verified end-to-end: Release archive + Developer ID export
  produces a valid signature with the entitlements and embedded profile.
  **Phase 2 verified 2026-06-11 on two real Macs (aerie → MarcusBook Pro):**
  fresh registration on Mac 1 wrote the synced item; iCloud Keychain
  delivered it to Mac 2 in ~2 minutes; the welcome-back card appeared and
  one click minted Mac 2 its own labeled token. Both devices online and
  merging in the feed. The whole flow is production-verified.
- Any valid token can mint more tokens (`POST /api/tokens`); revoking a token
  doesn't cascade to tokens it minted. Mitigated by full visibility in the
  device list. A "remove all other devices" affordance is a sensible
  follow-up.
- Handle edits in Settings are local-only (pre-existing), so the synced item
  mirrors whatever the local config says.
