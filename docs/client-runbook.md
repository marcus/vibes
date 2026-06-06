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
4. Add a config loader for tracked repos and relay URL.
5. Wire Scan Now to local aggregation.
6. Add relay publish/feed calls.

## Config Direction

Start with a local config file under Application Support:

```text
~/Library/Application Support/Vibes/config.yaml
```

Keep repo aliases opt-in. Do not publish raw repo paths, branch names, commit messages, or filenames by default.

## Xcode Project Notes

The project uses Xcode filesystem-synchronized groups. New Swift files under `client/Vibes/` should appear in the `Vibes` target automatically.

Keep the checked-in project buildable with `make client`.
