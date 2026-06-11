# Isolated UI testing (throwaway app instance)

How to run a fully configured, disposable Vibes instance for UI verification
without touching the real account, config, or keychain. Verified 2026-06-11
while polishing the new-user experience.

## Recipe

1. **Build a Debug app** (xcodebuild needs full Xcode, not just CLT):

   ```bash
   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
     xcodebuild -project client/Vibes.xcodeproj -scheme Vibes \
     -configuration Debug -destination 'platform=macOS' build
   ```

   The product lands in `~/Library/Developer/Xcode/DerivedData/Vibes-*/Build/Products/Debug/Vibes.app`.

2. **Run the local relay** (`cd server && npm run dev`, port 5173) and register
   a test account:

   ```bash
   curl -s -X POST http://localhost:5173/api/register \
     -H 'Content-Type: application/json' \
     -d '{"handle":"ui-test","displayName":"UI Test","deviceLabel":"TestMac"}'
   # → { user: {...}, token: "..." }
   ```

3. **Create a fake home** with a ready-made config and dev token:

   ```bash
   FAKE=/tmp/vibes-ui-home
   mkdir -p "$FAKE/Library/Application Support/Vibes"
   # config.json: identity/device/server/repos/sharing/presence per
   # VibesConfig (Models.swift). relay_url http://localhost:5173 is allowed —
   # HTTP passes the relay-URL check only for localhost.
   # token.dev: the raw token, plaintext. Debug builds read token.dev before
   # the keychain (TokenStore in ConfigStore.swift), so no keychain prompt.
   printf '%s' "<token>" > "$FAKE/Library/Application Support/Vibes/token.dev"
   ```

4. **Launch with `CFFIXED_USER_HOME`** (launch the binary directly so env
   carries over):

   ```bash
   CFFIXED_USER_HOME=$FAKE \
     <DerivedData>/Build/Products/Debug/Vibes.app/Contents/MacOS/Vibes &
   ```

   Plain `HOME=` does **not** work — `NSHomeDirectory()`/`FileManager` resolve
   the home from the passwd entry and ignore the `HOME` env var;
   `CFFIXED_USER_HOME` is respected.

To exercise feed states, edit the fake config (e.g. add a repo with a real
local path to get live churn) and relaunch, or register a second account and
accept an invite between them for a populated sky.

## Gotchas

- **UserDefaults are NOT isolated.** `@AppStorage` goes through cfprefsd,
  which ignores the fake home — the test instance reads/writes the real
  `com.opentangle.vibes` prefs domain shared with the production app
  (`feedViewMode`, `feedTextSize`, window frames...). `defaults read` the keys
  you plan to poke first and restore them after.
- **Don't launch a Debug build against the real home.** The Debug code
  signature differs from the release Developer ID signature, so reading the
  existing keychain token triggers a login-password prompt (and `token.dev`
  doesn't exist in the real app support dir).
- The dev relay's SQLite keeps any test accounts you register; that's fine —
  it's local-only.

## Driving and capturing the UI from a script

- **Window screenshots:** `screencapture -x -l<windowID> out.png`. Get the
  window id with a small Swift script over `CGWindowListCopyWindowInfo`
  (filter `kCGWindowOwnerName == "Vibes"`, `kCGWindowLayer == 0`).
- **Clicks:** post `CGEvent` mouse events from a Swift CLI at window-relative
  coordinates (CGWindow bounds are in points, top-left origin), or use System
  Events AX clicks for named controls (settings toolbar tabs work:
  `click button "General" of toolbar 1 of window 1`).
- Both need the terminal to hold Screen Recording / Accessibility permissions
  (already granted on this machine).

## Platform note

macOS SwiftUI **ignores `.dynamicTypeSize()`** — text styles don't scale
(verified empirically against a live build). That's why the feed text size
setting is implemented as the `feedTextScale` environment multiplier
(`OrbitView.swift`) over explicit base font sizes. See "Feed text size" in
`client/Vibes/DESIGN.md`.
