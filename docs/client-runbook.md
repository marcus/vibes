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

## Core Features Implemented

1. **First-Launch Setup Panel**: Connection screen allows importing a JSON configuration file or inputting settings manually (relay URL, token, handle, display name, and device label).
2. **Settings/Config Store**: Configuration is persisted locally at `~/Library/Application Support/Vibes/config.json`. Repository aliases, sharing preferences, and display details are stored here.
3. **Secure Auth Storage**: Authentication tokens are stored securely in the macOS Keychain (`Vibes Relay` service) rather than in the configuration file.
4. **Git Scanner Service**: Scans uncommitted and committed changes since midnight for all tracked repositories, aggregating commits, files changed, insertions, deletions, and attributing work to configured agent types.
5. **Feed & Status Update**: Centralized state manager publishes local status updates and retrieves the merged feed (the user's status and friends' statuses) periodically.
6. **Presence Modes & Vibes**: Supports Broadcasting, Quiet, and Offline presence modes. Derived vibes are automatically computed from git activity levels (e.g. warming up, deep work, yak shaving, rage fixing).
7. **Invite Link Management**: Users can generate new single-use invite URLs, copy them to the clipboard, list pending invites, and revoke open invites directly from the app interface.
8. **Periodic Refresh Loop**: Background synchronizer scans, publishes, and fetches the feed every 3 minutes, with an immediate manual refresh trigger in the header.

## Core Architecture

- [AppModel.swift](file:///Users/marcusvorwaller/code/vibes/client/Vibes/AppModel.swift): Central `@MainActor` class managing app state, background loops, settings mutations, and Keychain interactions.
- [ConfigStore.swift](file:///Users/marcusvorwaller/code/vibes/client/Vibes/ConfigStore.swift): Manages saving/loading configuration JSON profiles.
- [GitScanner.swift](file:///Users/marcusvorwaller/code/vibes/client/Vibes/GitScanner.swift): Executes shell commands to scan repository changes since midnight.
- [ContentView.swift](file:///Users/marcusvorwaller/code/vibes/client/Vibes/ContentView.swift): Holds the primary user interface screens (`SetupPanel`, `MainPanel` with Feed, Repos, and Invites tabs).
- [Models.swift](file:///Users/marcusvorwaller/code/vibes/client/Vibes/Models.swift): Holds model types corresponding to the API contract.

## Config Direction

Start with a local JSON config file under Application Support:

```text
~/Library/Application Support/Vibes/config.json
```

Keep repo aliases opt-in. Do not publish raw repo paths, branch names, commit messages, or filenames by default. Store raw relay tokens in Keychain, not in config.

## Xcode Project Notes

The project uses Xcode filesystem-synchronized groups. New Swift files under `client/Vibes/` should appear in the `Vibes` target automatically.

Keep the checked-in project buildable with `make client`.

`GENERATE_INFOPLIST_FILE = NO`, so `client/Vibes/Info.plist` is authoritative. `CFBundleShortVersionString` and `CFBundleVersion` map to `$(MARKETING_VERSION)` / `$(CURRENT_PROJECT_VERSION)` build settings — bump versions in the project, not in the plist.

## Signed Release & Notarization

Vibes ships outside the Mac App Store as a Developer ID–signed, notarized app with in-app updates via Sparkle (integrated; see [docs/plans/active/client-auto-update.md](plans/active/client-auto-update.md)). Sparkle 2.x is added as a SwiftPM dependency (`Package.resolved` is committed), the updater is wired in [VibesApp.swift](file:///Users/marcusvorwaller/code/vibes/client/Vibes/VibesApp.swift) / [UpdaterController.swift](file:///Users/marcusvorwaller/code/vibes/client/Vibes/UpdaterController.swift), and the Sparkle keys live in `Info.plist`.

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
5. **Sparkle EdDSA keys** — done. The keypair was generated with Sparkle's `generate_keys`; the private key is in the login Keychain and the public key `BoFhKL3O/oB9tBt3cctygi6yv7qMpl7peOYiQ+SVqAA=` is set as `SUPublicEDKey` in `Info.plist`. Back up the private key with `generate_keys -x <file>` and store it somewhere safe — losing it means you can never ship a verifiable update to existing users.
6. **Appcast feed URL** — `SUFeedURL` is `https://vibes.opentangle.com/appcast.xml`, served as a static file from the existing deployment (nginx; see [server-runbook.md](server-runbook.md)). Publish `release/appcast/appcast.xml` to that path on each release. Update **zips** can live anywhere public — `VIBES_APPCAST_BASE_URL` controls their download prefix (GitHub Releases or the same host). Keep the feed URL stable forever once shipped.

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
| `VIBES_APPCAST_BASE_URL` | public download URL prefix for update archives |
| `VIBES_BUILD_DMG` | `1` to also build + notarize a DMG |

### Build a signed, notarized release

```bash
scripts/release-mac.sh          # archive → export → notarize → staple → verify → stage update zip
scripts/generate-appcast.sh     # EdDSA-sign archive + (re)generate release/appcast/appcast.xml
```

Then upload the update zip (and DMG, if built) to the release host and publish `release/appcast/appcast.xml` at the public appcast URL. See [release/README.md](../release/README.md) for the flow.

### Old-to-new update QA

Install an older signed/notarized build into `/Applications`, host a test appcast with a newer signed archive, and use `Vibes → Check for Updates...` to confirm download, relaunch on the new version, and preserved config. Confirm the installed `SUPublicEDKey` matches the key that signed the test archive. Build two versions by bumping `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION` between `release-mac.sh` runs.

### Troubleshooting

- **appcast 404 / invalid TLS** — appcast URL or host misconfigured; verify it loads over HTTPS.
- **`generate-appcast.sh` hangs** — it's blocked on a macOS Keychain prompt for the EdDSA key; click "Always Allow", or set `VIBES_ED_KEY_FILE` to sign non-interactively.
- **missing `CFBundleVersion`** — the app must carry version keys (it now does); a release with none breaks Sparkle version comparison.
- **EdDSA signature mismatch** — the installed app's `SUPublicEDKey` does not match the signing private key. Most common Sparkle failure.
- **app running from a read-only disk image** — updates can't apply; install to `/Applications` first.
- **notarization failure** — run `xcrun notarytool log <submission-id> --keychain-profile vibes-notary` to see the rejection reason (usually unsigned nested code or missing hardened runtime).
- **broken framework symlinks** — always package with `ditto -c -k --keepParent`, never `zip`, so signatures and symlinks survive.
