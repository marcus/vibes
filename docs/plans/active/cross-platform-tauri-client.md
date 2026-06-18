# Cross-Platform Tauri Client Plan

## Decision

Keep the native SwiftUI macOS app as the first-party Mac experience, and add a Tauri client as the cross-platform app for macOS, Linux, and Windows.

The Tauri app is not a replacement for the native Mac app. It is the portability lane: one codebase for people who want to run Vibes on Linux or Windows, plus a Mac build the team can test locally without needing a second operating system.

Do not pursue GTK or Electron for this track. GTK would make Linux feel native but leave Windows and Mac as second-class targets. Electron would move fastest but adds a large runtime and pushes the product away from the small, quiet desktop-object feeling. Tauri gives Vibes a small shell, a web UI surface that can share design tokens with the relay, and native platform hooks where they matter.

## Product Shape

Vibes should have two client families:

- **Native macOS client**: SwiftUI, Keychain, Sparkle, macOS Settings, menu bar companion, and the most polished Apple-platform feel.
- **Tauri client**: one portable desktop app for macOS, Linux, and Windows, with the same privacy contract, relay contract, local Git scanner behavior, manual status, online/offline control, invite flow, and friend feed.

The Tauri app should feel like Vibes, not like the web signup page dropped into a window. It should reuse the design language and tokens, but its first screen is the actual presence app: feed, status, mode toggle, scan state, and invite action.

## Goals

- Support Linux and Windows without weakening the local-scanning model.
- Let the team exercise the portable app on macOS during normal development.
- Keep the relay contract unchanged unless a shared-client gap proves otherwise.
- Preserve the privacy boundary: publish aggregate Git activity only, never raw repo paths, branch names, commit messages, filenames, raw hashes, editor activity, process history, transcripts, or code-origin attribution.
- Share scanner and contract logic across platforms where practical.
- Keep platform-specific storage, autostart, tray, updater, and packaging behind narrow adapters.

## Non-Goals

- Do not replace the native macOS app in the near term.
- Do not add GitHub-only presence as the Linux/Windows shortcut.
- Do not publish repo names by default on any platform.
- Do not build public discovery, broad social graph behavior, or productivity-dashboard features as part of this work.
- Do not scaffold a second UI framework before the portable core boundary is clear.

## Architecture

Split the portable client into three layers:

```text
relay API
  ^
  |
portable core
  - config model
  - API client
  - local Git scanner
  - privacy filtering
  - Vibes day window
  - status payload builder
  - feed models
  - periodic scan/publish/fetch loop
  ^
  |
platform shell
  - Tauri commands
  - secure storage adapter
  - filesystem picker
  - tray/menu integration
  - autostart adapter
  - updater/packaging adapter
  - Svelte UI
```

The portable core should not know whether it is running on macOS, Linux, or Windows except through injected adapters. It should produce the same publishable status shape as the SwiftUI client.

## Tauri Stack

Use:

- Tauri 2.
- Rust for the shell, platform adapters, secure storage bridge, and command boundary.
- Svelte or SvelteKit-style Svelte components for the UI. Prefer a plain Vite/Svelte app if the Tauri surface does not need SvelteKit routing.
- Shared TypeScript models generated from or checked against the existing relay contract fixtures.
- Existing web tokens from `server/src/lib/styles/tokens.css` as the visual source of truth, mirrored into the Tauri UI.

The Rust side should own local capabilities:

- Git process execution.
- Config file IO.
- Secure token storage.
- Native folder picker.
- Tray/menu actions.
- Autostart registration.
- Update integration.

The web side should own presentation:

- Setup.
- Feed.
- Manual status.
- Online/offline toggle.
- Repositories settings.
- Sharing toggles.
- Invite create/accept/revoke.
- Basic diagnostics.

## Portable Core Boundary

Start by extracting behavior, not by porting screens.

The first portable unit should cover:

- `VibesDayWindow` equivalent.
- Repo config shape.
- Git scanner behavior:
  - scan explicit repo paths only
  - use local Git CLI
  - count committed changes only
  - scan local branches
  - include both day start and day upper bound
  - compute aggregate totals
  - compute one-way commit fingerprints for relay-side dedupe
- Status payload builder:
  - online/offline mode
  - manual status
  - derived vibe label
  - aggregate Git stats cards
  - optional repo aliases
- Relay client:
  - register/link/import/hydrate
  - publish
  - feed
  - invite actions
  - device removal when supported

The SwiftUI app can keep its current Swift implementation until there is a strong reason to share a compiled core. The first Tauri version can reimplement the scanner in Rust as long as contract tests prove parity with Swift behavior.

## Platform Adapters

### macOS Tauri

Purpose: development and parity testing, not the preferred public Mac download.

- Secure storage: Keychain through a Rust crate or Tauri plugin.
- Config: `~/Library/Application Support/Vibes Tauri/config.json` or an equivalent app-specific support directory.
- Tray: macOS menu bar item.
- Autostart: Launch Services or Tauri autostart plugin.
- Updates: Tauri updater for the Tauri app only. Sparkle remains the native Mac app updater.
- Packaging: signed/notarized `.app`/DMG later, but early internal builds can be unsigned.

Avoid sharing the native app's Keychain items or config path at first. Explicit migration can come later; accidental cross-client mutation would be harder to debug.

### Linux

- Secure storage: Secret Service/libsecret when available.
- Fallback storage: encrypted local file only if the user explicitly accepts the weaker behavior, or a token re-entry flow if no secure store exists.
- Config: XDG config/data directories.
- Tray: AppIndicator where available, with graceful degradation when a desktop environment hides tray icons.
- Autostart: XDG autostart or systemd user unit, selected by what Tauri supports cleanly.
- Packaging: AppImage first for broad testing, `.deb` once Debian/Ubuntu users are real, Flatpak later only after filesystem permissions are understood.
- Repo access: make explicit folder selection required. Do not ask for broad home-directory access by default in sandboxed package formats.

### Windows

- Secure storage: Windows Credential Manager.
- Config: `%APPDATA%\Vibes\config.json` or the Tauri app config directory.
- Tray: Windows system tray.
- Autostart: Startup folder or registry-backed Tauri autostart plugin.
- Git discovery:
  - detect `git.exe` on `PATH`
  - support common Git for Windows install paths
  - produce clear setup guidance when Git is missing
- Path handling:
  - normalize Windows paths internally
  - never publish raw paths
  - handle spaces, drive letters, UNC paths, and non-ASCII paths in tests
- Packaging: MSI or NSIS installer after the first working alpha. Use code signing before public distribution.

## UI Scope For The First Tauri Alpha

The alpha should be small but real:

- First-launch setup:
  - create identity against a relay
  - link existing account with pairing code
  - import token manually as an advanced escape hatch
- Main panel:
  - friend feed
  - "you" status
  - manual status editor
  - online/offline toggle
  - scan/publish/fetch now
  - last sync state
- Repositories:
  - add folder
  - remove folder
  - alias
  - publish-alias toggle
- Invites:
  - create invite
  - copy invite link
  - accept invite code/link
  - list/revoke open invites if the relay supports it
- Sharing:
  - Git stats cards
  - repo aliases
  - profile icon/name basics
- Diagnostics:
  - relay URL
  - auth state
  - configured repo count
  - last scan result with paths redacted
  - export redacted diagnostics text

Skip heavier polish in the alpha:

- orbit view parity
- profile icon generation
- native Mac settings parity
- cross-client config migration
- auto-update
- Linux/Windows code signing
- elaborate onboarding animation

## Privacy Requirements

The Tauri app must enforce the same privacy rules as the native client before any publish call:

- Raw repo paths stay local.
- Branch names stay local.
- Commit messages stay local.
- Filenames stay local.
- Raw commit hashes stay local.
- Exact editor/window/process activity is never inspected.
- Agent/tool transcripts are never inspected.
- Coding-tool, editor, assistant, and human-vs-AI attribution remain out of scope.
- Repo aliases are opt-in per repo.
- Diagnostics redact repo paths and tokens by default.

The Rust command boundary should return redacted scan summaries to the UI unless a screen genuinely needs local-only sensitive detail, such as showing the configured repo path in settings.

## Contract And Test Strategy

Add shared fixtures before broad UI work:

- scanner fixture repos with known commits across branches and day windows
- relay request fixture for publish payload
- feed response fixture for rendering
- redaction fixture proving paths/messages/branches/filenames are absent from publishable JSON
- Windows path fixture
- Linux path fixture
- timezone boundary fixture

Minimum proof for the Tauri alpha:

- Rust scanner unit tests pass.
- Contract fixture tests pass.
- Tauri app launches on macOS.
- A local temp relay flow can register/link, add a repo, scan, publish, and fetch a feed.
- Screenshot proof of the running Tauri app on macOS.
- Manual or CI proof for Linux and Windows before calling those builds public.

## Rollout Phases

### Phase 0: Plan And Contract

- Land this plan.
- Identify Swift scanner behavior that must be matched.
- Add or confirm contract fixtures for status publish and feed.
- Decide Tauri workspace location, likely `tauri/` or `client-tauri/`.

### Phase 1: Portable Scanner Prototype

- Create the Tauri workspace.
- Implement Rust scanner parity for committed Git stats.
- Add redaction and publishable payload tests.
- Run against local fixture repos.

### Phase 2: Relay Integration

- Implement secure token storage adapters.
- Implement relay client commands.
- Support create identity, link account, hydrate account, publish, feed, and invites.
- Verify against a local relay.

### Phase 3: First Real UI

- Build the main panel, setup, repositories, sharing, and invite flows.
- Mirror the existing visual tokens without copying marketing-page layout.
- Add tray actions for show/hide, online/offline, scan now, and quit.
- Capture screenshot proof on macOS.

### Phase 4: Linux And Windows Hardening

- Test Git discovery and path handling.
- Verify secure storage behavior.
- Verify tray/autostart behavior.
- Package AppImage and Windows installer candidates.
- Document platform-specific setup and known desktop-environment caveats.

### Phase 5: Public Distribution

- Add update flow for the Tauri app.
- Add Linux and Windows release scripts.
- Add signing where practical:
  - Windows code signing before broad public download.
  - Linux checksum/signature artifacts.
  - macOS Tauri signing/notarization only if public Mac Tauri downloads become useful.
- Update download pages to present:
  - native macOS as the recommended Mac app
  - Tauri Linux
  - Tauri Windows
  - optional Tauri macOS test build only if intentionally published

## Open Questions

- Should the Tauri app use the same relay device model as the native app, or should device names include the platform by default?
- Should the native Mac app and Tauri Mac app ever share account bootstrap via Keychain, or should they remain deliberately separate?
- Which packaging target should be first for Linux users: AppImage or `.deb`?
- Is a headless CLI useful as a byproduct of the Rust core, or does that create support burden too early?
- Should contract models be generated from JSON Schema, or kept as hand-written types checked against fixtures?

## Definition Of Done For The Alpha

- A contributor can run the Tauri app on macOS and connect it to a local relay.
- A Linux user can run an unsigned/package test build, configure explicit repos, publish aggregate Git stats, and see friends.
- A Windows user can do the same with Git for Windows installed.
- The relay receives the same privacy-preserving payload shape as it receives from the SwiftUI client.
- Redaction tests prove no raw paths, branch names, commit messages, filenames, raw hashes, or token values enter publishable payloads or diagnostics.
- The native macOS app remains buildable and remains the recommended Mac client.
