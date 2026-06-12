# Client Runbook

The Vibes client is a native SwiftUI macOS app in `client/`.

## Open in Xcode

```bash
open client/Vibes.xcodeproj
```

Use the shared `Vibes` scheme.

## Command-Line Build

```bash
make client
```

Equivalent:

```bash
xcodebuild -project client/Vibes.xcodeproj -scheme Vibes -configuration Debug -destination 'platform=macOS' build
```

(`xcodebuild` needs full Xcode: prefix with
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` if the active
developer dir is the Command Line Tools.)

To run and verify UI changes against a disposable, fully configured instance
(local relay, fake home, scripted screenshots/clicks), see
[docs/ui-testing.md](ui-testing.md).

## Core Features Implemented

1. **First-Launch Setup Panel**: Create a new identity with just a display name, link to an existing account with a pairing code from another Mac ("Link this Mac", including `vibes://link/<code>?relay=…` deep links), continue one-click from an account found in iCloud Keychain ("Welcome back"), or use the Advanced paths (manual relay URL + token, JSON config import).
2. **Native Settings Window**: Configuration is edited through the macOS Settings scene (`Vibes → Settings...` / `Cmd-,`) with General, Profile Icon, Repositories, Sharing, and Advanced panes. General includes **Devices** (active per-device tokens with remove) and **Link Another Mac** (generate a single-use pairing code). Settings are persisted locally at `~/Library/Application Support/Vibes/config.json`.
3. **Secure Auth Storage**: The per-device token lives in the macOS Keychain (`com.marcusvorwaller.vibes.relay-token`). A second, iCloud-synchronizable item (`com.marcusvorwaller.vibes.account`) carries the account to the user's other Macs for the welcome-back flow — release builds only (see Signed Release: it requires the entitlements + embedded provisioning profile); in debug builds it degrades silently and logs the failing OSStatus. See [docs/plans/active/device-linking.md](plans/active/device-linking.md).
4. **Git Scanner Service**: Scans committed changes for the account-level Vibes day across all tracked repositories, aggregating commits, files changed, insertions, and deletions without publishing repo paths or code-origin attribution. Uncommitted (staged/unstaged) diffs are ignored — they carry no timestamp, so a stale dirty file would otherwise count as today's activity indefinitely.
5. **Feed & Status Update**: Centralized state manager publishes local status updates and retrieves the merged feed (the user's status and friends' statuses) periodically.
6. **Presence**: Two states — online and offline — derived from recent activity. You are online when you have published within the recency window and have not hidden yourself; a one-tap Offline toggle hides you immediately. Stale online presence reads as "online … ago" from the last update.
7. **Invite Friend Sheet**: Users can generate new single-use invite URLs, copy or share them, accept invite codes, list open invites, and revoke open invites from the main-window Invite action, empty feed state, or menu bar companion.
8. **Periodic Refresh Loop**: Background synchronizer scans, publishes, and fetches the feed every 3 minutes, with an immediate manual refresh trigger in the header.

## Core Architecture

- [AppModel.swift](file:///Users/marcus/code/vibes/client/Vibes/AppModel.swift): Central `@MainActor` class managing app state, background loops, settings mutations, and Keychain interactions.
- [ConfigStore.swift](file:///Users/marcus/code/vibes/client/Vibes/ConfigStore.swift): Manages saving/loading configuration JSON profiles.
- [GitScanner.swift](file:///Users/marcus/code/vibes/client/Vibes/GitScanner.swift): Executes shell commands to scan repository changes inside the account Vibes day window.
- [ContentView.swift](file:///Users/marcus/code/vibes/client/Vibes/ContentView.swift): Holds the primary user interface screens (`SetupPanel`, `MainPanel` with feed/status controls, native Settings panes, and the Invite Friend sheet).
- [Models.swift](file:///Users/marcus/code/vibes/client/Vibes/Models.swift): Holds model types corresponding to the API contract.

## Config Direction

Start with a local JSON config file under Application Support:

```text
~/Library/Application Support/Vibes/config.json
```

Keep repo aliases opt-in. Do not publish raw repo paths, branch names, commit messages, or filenames by default. Store raw relay tokens in Keychain, not in config.

`identity.timezone` stores the account Vibes day timezone. Registration sends `TimeZone.current.identifier`; imported or manually-entered tokens are hydrated from authenticated `/api/me` when the relay has an account timezone. If a config has no timezone and the relay cannot provide one yet, publishing falls back locally to the Mac timezone without changing the server account timezone.

## Xcode Project Notes

The project uses Xcode filesystem-synchronized groups. New Swift files under `client/Vibes/` should appear in the `Vibes` target automatically.

Keep the checked-in project buildable with `make client`.

`GENERATE_INFOPLIST_FILE = NO`, so `client/Vibes/Info.plist` is authoritative. `CFBundleShortVersionString` and `CFBundleVersion` map to `$(MARKETING_VERSION)` / `$(CURRENT_PROJECT_VERSION)` build settings — bump versions in the project, not in the plist.

## Signed Release & Notarization

Vibes ships outside the Mac App Store as a Developer ID–signed, notarized app with in-app updates via Sparkle (integrated; see [docs/plans/active/client-auto-update.md](plans/active/client-auto-update.md)). Sparkle 2.x is added as a SwiftPM dependency (`Package.resolved` is committed), the updater is wired in [VibesApp.swift](file:///Users/marcus/code/vibes/client/Vibes/VibesApp.swift) / [UpdaterController.swift](file:///Users/marcus/code/vibes/client/Vibes/UpdaterController.swift), and the Sparkle keys live in `Info.plist`.

### One-time setup (requires your Apple Developer account)

1. **Apple Developer Program membership** — required to issue a Developer ID certificate.
2. **Developer ID Application certificate** — create in Xcode (Settings → Accounts → Manage Certificates → + → Developer ID Application) or at developer.apple.com. Confirm with:

   ```bash
   security find-identity -v -p codesigning | grep "Developer ID Application"
   ```

   The installed identity is `Developer ID Application: Marcus Vorwaller (H5G3VW27DZ)`.
3. **notarytool credentials** — store a reusable keychain profile:

   ```bash
   # Recommended: App Store Connect API key (Keys tab → generate, role "Developer")
   scripts/setup-notary.sh api vibes-notary <KEY_ID> <ISSUER_ID> /path/to/AuthKey_XXXX.p8
   # Or an app-specific password:
   scripts/setup-notary.sh password vibes-notary marcus@vorwaller.net <TEAM_ID>
   ```
4. **Bundle id** — `PRODUCT_BUNDLE_IDENTIFIER` is set to `com.opentangle.vibes`. This is permanent once an update-capable build ships; do not change it.
4b. **Developer ID provisioning profile** — done; lives in the repo at `client/signing/Vibes_Developer_ID.provisionprofile` (expires **2027-02-01**). Required because the Release config signs with `client/Vibes/Vibes.entitlements` (`keychain-access-groups`, needed for the iCloud Keychain account hand-off) and restricted entitlements are only honored with an embedded profile. `release-mac.sh` installs it and passes `PROVISIONING_PROFILE_SPECIFIER`; `ExportOptions.plist` embeds it on export. If the Developer ID certificate ever rotates, regenerate the profile at developer.apple.com (Profiles → Developer ID → App ID `com.opentangle.vibes`) — and note the portal lists **two** same-named Developer ID Application certs; pick the one whose serial matches `security find-certificate -c "Developer ID Application: Marcus Vorwaller" -p | openssl x509 -noout -serial`.
5. **Sparkle EdDSA keys** — done. The keypair was generated with Sparkle's `generate_keys`; the private key is in the login Keychain and the public key `BoFhKL3O/oB9tBt3cctygi6yv7qMpl7peOYiQ+SVqAA=` is set as `SUPublicEDKey` in `Info.plist`. Back up the private key with `generate_keys -x <file>` and store it somewhere safe — losing it means you can never ship a verifiable update to existing users.
6. **Appcast feed URL** — `SUFeedURL` is `https://vibes.opentangle.com/appcast.xml`, served as a static file from the existing deployment (nginx; see [server-runbook.md](server-runbook.md)). Publish `release/appcast/appcast.xml` to that path on each release. Update **zips** and first-download DMGs are self-hosted under `https://vibes.opentangle.com/downloads`; `VIBES_APPCAST_BASE_URL` must be `https://vibes.opentangle.com/downloads` for public releases. Keep the feed URL stable forever once shipped.

### Required release environment variables

Copy `.env.release.example` to `.env.release` (gitignored) and fill it in. Team ID `H5G3VW27DZ` and the Developer ID identity are pre-filled.

| Variable | Meaning |
| --- | --- |
| `VIBES_BUNDLE_ID` | reverse-DNS app id for the public build |
| `VIBES_DEVELOPMENT_TEAM` | Apple Developer Team ID |
| `VIBES_CODESIGN_IDENTITY` | full `Developer ID Application: …` identity string |
| `VIBES_NOTARY_PROFILE` | notarytool keychain profile name |
| `VIBES_RELEASE_VERSION` | must equal project `MARKETING_VERSION` |
| `VIBES_BUILD_NUMBER` | integer, must exceed last released build |
| `VIBES_APPCAST_BASE_URL` | public download URL prefix for update archives; public releases use `https://vibes.opentangle.com/downloads` |
| `VIBES_BUILD_DMG` | `1` to also build + notarize a DMG; `make mac-release` sets this for the first-download artifact |

### Local release sequence

```bash
open client/Vibes.xcodeproj
# Bump MARKETING_VERSION and CURRENT_PROJECT_VERSION in the Vibes target.

$EDITOR release/release-notes/<version>.md

cp .env.release.example .env.release
$EDITOR .env.release
# Set VIBES_RELEASE_VERSION=<version>
# Set VIBES_BUILD_NUMBER=<integer greater than the previous public build>
# Confirm VIBES_APPCAST_BASE_URL=https://vibes.opentangle.com/downloads

make mac-release
```

Before building anything, `release-mac.sh` runs **`scripts/preflight-release.sh`**, which fails fast (milliseconds) if any of these are wrong: required env vars, `VIBES_RELEASE_VERSION` vs the project's `MARKETING_VERSION`, the release-notes file, the Developer ID signing identity in the keychain, the notarytool profile, and — critically — that the EdDSA signing key's public half equals the app's `SUPublicEDKey` (signing with the wrong key ships an update every installed app rejects). Run `make mac-preflight` any time to check readiness without building.

If a step *after* the build fails (e.g. appcast signing or upload), don't rerun the whole thing — the build artifacts are already notarized. Resume with **`make mac-publish`**, which only signs the staged appcast and publishes.

`scripts/release-mac.sh` validates that `VIBES_RELEASE_VERSION` equals the project's `MARKETING_VERSION`, uses `VIBES_BUILD_NUMBER` as `CURRENT_PROJECT_VERSION`, archives the app, exports a Developer ID build, notarizes and staples the app, verifies code signing/Gatekeeper, creates `release/appcast/Vibes-<version>.zip`, and with `VIBES_BUILD_DMG=1` creates/notarizes/staples `build/Vibes-<version>.dmg`.

`scripts/generate-appcast.sh` signs the update archive with Sparkle's EdDSA private key and regenerates `release/appcast/appcast.xml`.

`scripts/publish-mac-release.sh` requires `.env.deploy` plus `.env.release`, including an explicit `DEPLOY_USER`. It uploads to `${DEPLOY_PATH}/releases`, refuses to overwrite existing versioned artifacts with different content, atomically repoints `/downloads/Vibes.dmg`, writes and uploads `build/latest.json` to `/downloads/latest.json`, uploads `/downloads/SHA256SUMS`, and smoke-checks the public URLs.

After `make mac-release` succeeds:

1. Open `https://vibes.opentangle.com/download`.
2. Download and install the DMG into `/Applications`.
3. Run old-version-to-new-version Sparkle QA before announcing the release.

See [release/README.md](../release/README.md) and the [server runbook](server-runbook.md#auto-update-channel) for the public URL model, remote layout, and rollback commands.

### Old-to-new update QA

Install an older signed/notarized build into `/Applications`, publish or host an appcast with a newer signed archive, and use `Vibes → Check for Updates...` to confirm Sparkle sees the update, shows the release notes, downloads the expected `Vibes-<version>.zip`, relaunches on the new version/build, and preserves config. Confirm the installed `SUPublicEDKey` matches the key that signed the archive. Build two versions by bumping `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION` between `release-mac.sh` runs.

Do this against the public release channel after `make mac-release`: the old installed app should update from `https://vibes.opentangle.com/appcast.xml` to the just-published build.

### Troubleshooting

- **`No certificate for team … found` / `0 valid identities found`** — the Developer ID Application certificate and/or its private key is not in the keychain on this machine. `release-mac.sh` now preflights this and fails fast before archiving. Fix by installing the cert **with its private key**: Xcode → Settings → Accounts → Manage Certificates → + → Developer ID Application, or `security import DeveloperID.p12 -k login.keychain`. A cert created on another Mac needs its private key exported there (`.p12`) and imported here — the public certificate alone cannot sign. Verify with `security find-identity -v -p codesigning`. This is an environment-only failure; it never touches the published release.
- **appcast 404 / invalid TLS** — appcast URL or host misconfigured; verify it loads over HTTPS.
- **`generate-appcast.sh` hangs** — it's blocked on a macOS Keychain prompt for the EdDSA key; click "Always Allow", or set `VIBES_ED_KEY_FILE` to sign non-interactively.
- **missing `CFBundleVersion`** — the app must carry version keys (it now does); a release with none breaks Sparkle version comparison.
- **EdDSA signature mismatch** — the installed app's `SUPublicEDKey` does not match the signing private key. Most common Sparkle failure.
- **app running from a read-only disk image** — updates can't apply; install to `/Applications` first.
- **notarization failure** — run `xcrun notarytool log <submission-id> --keychain-profile vibes-notary` to see the rejection reason (usually unsigned nested code or missing hardened runtime).
- **release app killed instantly at launch (exit 137)** — the Release entitlements were signed without the embedded provisioning profile (AMFI kills restricted entitlements it can't authorize). Make sure `client/signing/Vibes_Developer_ID.provisionprofile` exists, `release-mac.sh` installed it, and the export used `ExportOptions.plist`'s `provisioningProfiles` mapping. Check the built app with `codesign -d --entitlements - Vibes.app` and `ls Vibes.app/Contents/embedded.provisionprofile`.
- **iCloud welcome-back never appears / `-34018` in DEBUG logs** — expected in debug builds (no entitlements by design). In a release build, verify the entitlements + embedded profile as above, and that both Macs use the same Apple ID with iCloud Keychain enabled.
- **broken framework symlinks** — always package with `ditto -c -k --keepParent`, never `zip`, so signatures and symlinks survive.
