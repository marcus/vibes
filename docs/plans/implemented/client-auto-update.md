# Vibes macOS auto-update plan

Status: implemented (moved from active 2026-08-21).

## Decision

Use Sparkle 2 for the Vibes macOS app. Vibes will never ship through the Mac App Store, and Sparkle is the standard path for a native macOS app distributed directly from a website or GitHub Releases. It gives Vibes a familiar "Check for Updates..." flow, optional background checks, EdDSA-signed update archives, appcast feeds, delta updates, and compatibility with Developer ID signed/notarized apps.

For production releases, use this stack:

- Sparkle 2 via Swift Package Manager.
- GitHub Releases for public release artifacts.
- A static HTTPS appcast, preferably GitHub Pages or `https://vibes.<domain>/appcast.xml`.
- Developer ID signing and notarization for public builds.
- Sparkle EdDSA signatures for every update archive.

Do not build a custom updater in v1. The only acceptable fallback is a documented "manual download" link for contributors who build unsigned forks.

## Current repo facts

- Client target: `client/Vibes.xcodeproj`, scheme `Vibes`.
- macOS deployment target: `14.0`.
- Bundle identifier: `com.opentangle.vibes` (set in the project; permanent once an update-capable build ships).
- Current versions: `MARKETING_VERSION = 0.1.0`, `CURRENT_PROJECT_VERSION = 1`.
- Hardened runtime is already enabled.
- The checked-in project uses filesystem-synchronized groups, so new Swift files under `client/Vibes/` should appear in the target automatically.
- `client/Vibes/Info.plist` is checked in and currently does not include version keys or Sparkle keys.
- `GENERATE_INFOPLIST_FILE = NO` and `INFOPLIST_FILE = Vibes/Info.plist` in both Debug and Release. The checked-in `Info.plist` is therefore authoritative; version and Sparkle keys must be added to it by hand. Do not flip `GENERATE_INFOPLIST_FILE` to `YES`, or Xcode will synthesize a second set of `CFBundleShortVersionString`/`CFBundleVersion` values and the keys will conflict.
- The app is not sandboxed (no App Sandbox entitlement), so Sparkle's `SUEnable*Service` sandboxing keys are not required.
- `make client` is the required client build check (`xcodebuild ... -configuration Debug ... build`).

## Release policy

Set the release identity before the first public build:

- `PRODUCT_BUNDLE_IDENTIFIER`: `com.opentangle.vibes` (already set).
- `MARKETING_VERSION`: human version, SemVer-like, for example `0.2.0`.
- `CURRENT_PROJECT_VERSION`: monotonically increasing integer build number. Never decrease it after any update-capable build has shipped.
- `CFBundleShortVersionString`: must resolve to `$(MARKETING_VERSION)`.
- `CFBundleVersion`: must resolve to `$(CURRENT_PROJECT_VERSION)`.

Do not ship Sparkle to users until bundle id, appcast URL, EdDSA public key, signing identity, and notarization flow are stable. Sparkle can rotate keys later, but the first release should avoid needless churn.

## Phase 1: Add Sparkle to the app target

1. Add the Sparkle package to the Xcode project:
   - Repository URL: `https://github.com/sparkle-project/Sparkle`
   - Product: `Sparkle`
   - Target: `Vibes`
   - Version rule: up to next major from the latest stable 2.x release. As of June 2026, Sparkle 2.9.2 is the current stable release; confirm the latest 2.x at implementation time and let the version rule float, rather than pinning to an exact tag.
   - Commit the resulting `project.pbxproj` and `client/Vibes.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` if Xcode creates it.

2. Verify the target links and embeds Sparkle:
   - `Sparkle.framework` must be linked to the `Vibes` target.
   - The framework must be embedded in `Vibes.app/Contents/Frameworks`.
   - The embedding mode should be "Embed & Sign".
   - `LD_RUNPATH_SEARCH_PATHS` already contains `@executable_path/../Frameworks`; keep it.

3. Keep the project buildable from the command line:
   - Run `make client`.
   - If SwiftPM resolution causes Xcode noise, commit only the stable files needed for repeatable builds.

## Phase 2: Configure Info.plist

Add these keys to `client/Vibes/Info.plist`:

```xml
<key>CFBundleShortVersionString</key>
<string>$(MARKETING_VERSION)</string>
<key>CFBundleVersion</key>
<string>$(CURRENT_PROJECT_VERSION)</string>
<key>SUFeedURL</key>
<string>https://updates.example.com/vibes/appcast.xml</string>
<key>SUPublicEDKey</key>
<string>REPLACE_WITH_SPARKLE_PUBLIC_ED25519_KEY</string>
<key>SUEnableAutomaticChecks</key>
<true/>
<key>SUAutomaticallyUpdate</key>
<false/>
<key>SUVerifyUpdateBeforeExtraction</key>
<true/>
```

Replace the feed URL and public key before release. Keep automatic checks enabled but automatic installation disabled by default. That fits Vibes: quiet background checking, but no surprising app replacement.

Note on `SUEnableAutomaticChecks`: hardcoding it to `true` suppresses Sparkle's first-launch "Check for updates automatically?" consent prompt and opts the user in silently. That is the intended behavior here, but if a visible opt-in is later preferred, remove this key and let Sparkle ask on first launch. Optionally set `SUScheduledCheckInterval` (seconds) to tune the background cadence; the default is daily.

Optional later hardening:

- `SURequireSignedFeed = true` after the release pipeline signs appcast and release notes reliably. Pair it with `SUVerifyUpdateBeforeExtraction` (already enabled above) and, optionally, `SUSignedFeedFailureExpirationInterval` to bound how long a previously-validated feed is trusted if signing later breaks.
- Do not enable Sparkle system profiling (`SUEnableSystemProfiling`); it defaults off, so simply omit it.
- Do not allow JavaScript in release notes (`SUEnableJavaScript` defaults off; do not add it).

## Phase 3: Wire the SwiftUI update UI

Add a small updater wrapper in `client/Vibes/UpdaterController.swift`:

```swift
import Sparkle
import SwiftUI

final class CheckForUpdatesViewModel: ObservableObject {
  @Published var canCheckForUpdates = false

  init(updater: SPUUpdater) {
    updater.publisher(for: \.canCheckForUpdates)
      .assign(to: &$canCheckForUpdates)
  }
}

struct CheckForUpdatesView: View {
  @ObservedObject private var viewModel: CheckForUpdatesViewModel
  private let updater: SPUUpdater

  init(updater: SPUUpdater) {
    self.updater = updater
    self.viewModel = CheckForUpdatesViewModel(updater: updater)
  }

  var body: some View {
    Button("Check for Updates...", action: updater.checkForUpdates)
      .disabled(!viewModel.canCheckForUpdates)
  }
}
```

Update `client/Vibes/VibesApp.swift`:

```swift
import Sparkle

@main
struct VibesApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @StateObject private var model = AppModel()
  private let updaterController = SPUStandardUpdaterController(
    startingUpdater: true,
    updaterDelegate: nil,
    userDriverDelegate: nil
  )

  var body: some Scene {
    WindowGroup {
      ContentView()
        .environmentObject(model)
        .onAppear {
          AppDelegate.model = model
        }
    }
    .windowResizability(.contentSize)
    .commands {
      CommandGroup(after: .appInfo) {
        CheckForUpdatesView(updater: updaterController.updater)
      }
    }

    MenuBarExtra("Vibes", systemImage: "dot.radiowaves.left.and.right") {
      Button("Show Vibes") {
        NSApp.activate(ignoringOtherApps: true)
      }
      CheckForUpdatesView(updater: updaterController.updater)
      Divider()
      ...
    }
  }
}
```

Reuse the same `CheckForUpdatesView` in both the command menu and the `MenuBarExtra`. It observes `canCheckForUpdates` through the published view model, so its disabled state refreshes correctly in both places. Do not bind `.disabled(!updaterController.updater.canCheckForUpdates)` directly to the raw KVO property — SwiftUI does not observe it, so the item would render with a stale enabled/disabled state. Do not build custom Sparkle UI in v1.

## Phase 4: Add release assets and scripts

Create a release folder layout:

```text
release/
  README.md
  appcast/
    appcast.xml
  release-notes/
    0.2.0.md
scripts/
  release-mac.sh
  generate-appcast.sh
  ExportOptions.plist
```

The `ExportOptions.plist` does not exist yet and must be created and checked in. Use a Developer ID template (no secrets in it — team id is not a secret, but keep it overridable via the env var if preferred):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>developer-id</string>
  <key>signingStyle</key>
  <string>manual</string>
  <key>teamID</key>
  <string>REPLACE_WITH_TEAM_ID</string>
</dict>
</plist>
```

Do not commit private keys, exported certificates, notarization passwords, `.xcarchive`, `.dmg`, `.zip`, `.aar`, or database-like release state.

`scripts/release-mac.sh` should:

1. Require these environment variables:
   - `VIBES_BUNDLE_ID`
   - `VIBES_DEVELOPMENT_TEAM`
   - `VIBES_CODESIGN_IDENTITY`
   - `VIBES_NOTARY_PROFILE` or equivalent notarytool credentials
   - `VIBES_RELEASE_VERSION`
   - `VIBES_BUILD_NUMBER`
   - `VIBES_APPCAST_BASE_URL`

2. Validate version inputs:
   - `VIBES_RELEASE_VERSION` must match `MARKETING_VERSION`.
   - `VIBES_BUILD_NUMBER` must be greater than the last released `CURRENT_PROJECT_VERSION`.

3. Build an archive:

```bash
xcodebuild archive \
  -project client/Vibes.xcodeproj \
  -scheme Vibes \
  -configuration Release \
  -archivePath build/Vibes.xcarchive \
  MARKETING_VERSION="$VIBES_RELEASE_VERSION" \
  CURRENT_PROJECT_VERSION="$VIBES_BUILD_NUMBER" \
  PRODUCT_BUNDLE_IDENTIFIER="$VIBES_BUNDLE_ID" \
  DEVELOPMENT_TEAM="$VIBES_DEVELOPMENT_TEAM" \
  CODE_SIGN_IDENTITY="$VIBES_CODESIGN_IDENTITY"
```

4. Export a Developer ID app using `xcodebuild -exportArchive -exportOptionsPlist scripts/ExportOptions.plist` (the checked-in template above), with its placeholder values documented in `docs/client-runbook.md`.

5. Notarize and staple the exported app bundle before creating release artifacts:

```bash
ditto -c -k --keepParent build/export/Vibes.app build/notary/Vibes-app.zip
xcrun notarytool submit build/notary/Vibes-app.zip --keychain-profile "$VIBES_NOTARY_PROFILE" --wait
xcrun stapler staple build/export/Vibes.app
```

6. Package the stapled app:
   - Preferred first-download artifact: `.dmg` with `/Applications` symlink.
   - Preferred Sparkle update artifact: `.zip` containing only `Vibes.app`, created from the stapled app.
   - Use `ditto -c -k --keepParent` for zip archives so code signatures and symlinks are preserved.
   - A `.dmg` can also be used as the Sparkle update archive, but using a zip for updates keeps the appcast smaller and simpler.

7. Notarize and staple the DMG if publishing one:

```bash
xcrun notarytool submit build/Vibes.dmg --keychain-profile "$VIBES_NOTARY_PROFILE" --wait
xcrun stapler staple build/Vibes.dmg
spctl --assess --type open --context context:primary-signature --verbose build/Vibes.dmg
```

8. Verify the app bundle:

```bash
codesign --verify --deep --strict --verbose=2 build/export/Vibes.app
spctl --assess --type execute --verbose build/export/Vibes.app
```

9. Copy the update zip and matching release notes into the appcast staging folder.

`scripts/generate-appcast.sh` should:

1. Locate Sparkle's `generate_appcast`.
   - Preferred: use `SPARKLE_BIN` pointing at an unpacked Sparkle distribution archive.
   - Acceptable local fallback: find it under DerivedData's SwiftPM artifact path after package resolution.
   - Fail with a clear message if it cannot be found.
2. Run `generate_appcast` against the folder containing all shipped update archives, using the configured download URL prefix for public artifact URLs.
3. Produce or update `release/appcast/appcast.xml`.
4. Fail if the generated appcast does not contain the expected build number, archive URL, archive length, and EdDSA signature.
5. Confirm each item carries a `sparkle:minimumSystemVersion` of at least `14.0` (matching the deployment target) so Sparkle does not offer the update to incompatible systems. `generate_appcast` infers this from the app bundle's `LSMinimumSystemVersion`; if absent, set it explicitly.
6. Print the files that must be uploaded.

## Phase 5: Sparkle keys

Generate a Sparkle EdDSA keypair once:

```bash
path/to/Sparkle/bin/generate_keys
```

Handling rules:

- Private key stays in the release maintainer's macOS Keychain or another secure local secret store.
- Public key goes into `SUPublicEDKey`.
- Never commit private key material or copy it into CI logs.
- Document the key owner and recovery process in a private operations note, not in this public repo.
- If using CI, prefer manual notarized releases first; add CI release automation only after signing and key storage are mature.

## Phase 6: Hosting model

Recommended for v1:

- Upload `Vibes-<version>.dmg` or `Vibes-<version>.zip` to GitHub Releases.
- Host `appcast.xml` and release notes on GitHub Pages or the Vibes public website over HTTPS.
- Keep the appcast URL stable forever once public builds exist.

Do not host appcasts on the private relay API unless there is a product reason. The update channel is public software distribution, not friend presence data, and should not depend on a user's relay instance.

Use separate feeds if needed:

- Stable: `/appcast.xml`
- Beta: `/appcast-beta.xml`

Do not ship beta-channel UI in v1. A beta feed can be used manually for local QA by temporarily changing `SUFeedURL` in a development build.

## Phase 7: End-to-end QA

Perform this before the first public release and before every release script change:

1. Build and install an older signed/notarized Vibes build into `/Applications`.
2. Confirm the old build has lower `CURRENT_PROJECT_VERSION`.
3. Host a test appcast with a newer signed update archive. Confirm the `SUPublicEDKey` baked into the older installed app matches the private key that signed this archive — a key mismatch is the most common cause of a silent "no updates" or signature-verification failure.
4. Launch the older app.
5. Use `Vibes > Check for Updates...`.
6. Confirm Sparkle shows release notes and downloads the expected artifact.
7. Complete the update.
8. Confirm Vibes relaunches on the newer version.
9. Confirm user config under Application Support is preserved.
10. Confirm no raw repo paths, tokens, commit messages, branch names, filenames, or local activity details are sent to update hosting.
11. Check Console.app logs for Sparkle errors.

CLI verification after update:

```bash
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' /Applications/Vibes.app/Contents/Info.plist
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' /Applications/Vibes.app/Contents/Info.plist
codesign --verify --deep --strict --verbose=2 /Applications/Vibes.app
spctl --assess --type execute --verbose /Applications/Vibes.app
```

For UI proof, capture a screenshot of the Sparkle update dialog during the QA run and attach it to the implementing PR or handoff.

## Phase 8: Documentation updates

Update `docs/client-runbook.md` with:

- How to build Debug locally.
- How to build a signed Release archive.
- Required release environment variables.
- How to generate Sparkle keys.
- Where the public appcast lives.
- How to publish a release.
- How to run the old-version-to-new-version QA test.
- Troubleshooting:
  - appcast 404 or invalid TLS
  - missing `CFBundleVersion`
  - EdDSA signature mismatch
  - app running from a read-only disk image
  - notarization failure
  - copied framework symlinks broken by packaging

Update `README.md` only with a short "Releases" section that points to the runbook. Keep detailed release instructions in the runbook.

## Definition of done for implementation

An implementing agent is done only when:

- `make client` passes.
- Sparkle is linked and embedded in the app bundle.
- `Info.plist` includes version keys and Sparkle keys with real production values or clearly documented placeholders if the release identity is intentionally deferred.
- The app menu contains `Check for Updates...`.
- The menu item is disabled when Sparkle cannot check.
- Release scripts exist and fail fast on missing signing/notarization/appcast inputs.
- A generated appcast includes an EdDSA signature for a local test artifact.
- A local old-version-to-new-version Sparkle update has been performed, or the exact blocker is recorded.
- Code-changing commits receive independent review per `AGENTS.md`.
- The handoff includes test output and update-dialog proof for UI/release behavior.

## References

- Sparkle documentation: https://sparkle-project.github.io/documentation/
- Sparkle programmatic SwiftUI setup: https://sparkle-project.github.io/documentation/programmatic-setup/
- Sparkle publishing guide: https://sparkle-project.github.io/documentation/publishing/
- Sparkle customization keys: https://sparkle-project.github.io/documentation/customization/
- Sparkle GitHub repository: https://github.com/sparkle-project/Sparkle
