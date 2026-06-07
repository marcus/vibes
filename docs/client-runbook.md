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
