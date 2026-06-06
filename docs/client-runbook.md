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

## First Implementation Tasks

1. Replace the placeholder panel with the first real friend feed UI.
2. Add a local model for `PresenceMode`, `ManualStatus`, `DailyGitStats`, and `FriendStatus`.
3. Build a local Git scanner service using `git log --since=midnight --numstat --pretty=format:`, `git diff --numstat`, and `git diff --cached --numstat`.
4. Add first-launch setup for importing config JSON or pasting relay URL plus one-time token.
5. Add a config loader for tracked repos and relay URL.
6. Store relay tokens in Keychain and remove raw tokens from persisted config.
7. Add an automatic scan/publish/feed refresh loop.
8. Keep manual refresh as a secondary/debug action.
9. Add relay publish/feed calls.

## Config Direction

Start with a local JSON config file under Application Support:

```text
~/Library/Application Support/Vibes/config.json
```

Keep repo aliases opt-in. Do not publish raw repo paths, branch names, commit messages, or filenames by default. Store raw relay tokens in Keychain, not in config.

## Xcode Project Notes

The project uses Xcode filesystem-synchronized groups. New Swift files under `client/Vibes/` should appear in the `Vibes` target automatically.

Keep the checked-in project buildable with `make client`.
