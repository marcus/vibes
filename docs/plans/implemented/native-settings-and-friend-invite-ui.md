# Native Settings Window and Friend Invite UI

Status: implemented (moved from active 2026-08-21).

## Goal

Make Vibes feel like a normal, well-behaved Mac app:

- App configuration lives in a standard macOS Settings window opened from `Vibes > Settings...` and `Cmd-,`.
- Friend setup leaves Settings and becomes a first-class social action in the main window and menu bar companion.
- The implementation keeps Vibes quiet, private, and small, without turning settings into a dashboard.

## Recommendation

Use a native SwiftUI `Settings` scene for configuration and a separate "Invite a Friend" sheet/window for friend connection.

Settings should answer "how does this app behave on my Mac?" Inviting should answer "who do I want to connect with right now?" Those are different user intentions. Apple guidance points in the same direction: macOS app-specific settings belong in a separate Settings window accessible from the app menu, while sheets are best for scoped tasks closely related to the current context. Creating or accepting a friend invite is a scoped task, not a durable preference.

## Apple Guidance Basis

- Apple describes macOS app settings as a separate window accessed from the app menu.
- Apple's Settings HIG recommends a visible, noncustomizable toolbar for a macOS settings window, with the active toolbar item indicated.
- Apple's sheet guidance frames sheets as modal, targeted tasks that collect information or complete a short action before returning to the parent view.

## Current State

`ContentView.swift` currently presents `SettingsView` as a custom sheet from the footer gear. That sheet mixes:

- repositories,
- invite creation and invite acceptance,
- pending invite management,
- advanced LLM guidance and diagnostics.

This works for the hackathon path, but it does not match the product model in `spec-v2.md`, which already says:

- Settings should cover repos, sharing, identity, relay, and advanced guidance/diagnostics.
- Inviting is a primary action exposed from the main window header and menu bar companion.

## Target UX

### Main Window

Keep the main window focused on presence:

- Header: app mark/name, sync affordance, and an `Invite` button.
- Body: friend feed.
- Footer: own Online/Offline control and manual status.
- Empty feed state: include the same `Invite` action.

The footer gear can remain as a secondary way to open Settings, but it should call the same app-level Settings command instead of presenting a custom settings sheet.

### Settings Window

Create a native `Settings` scene in `VibesApp.swift`.

Use a compact toolbar/tab structure:

1. `General`
   - Display name.
   - Handle.
   - Device label.
   - Relay URL.
   - Read-only account/device identifiers where useful.

2. `Repositories`
   - Add repository with folder picker.
   - Remove repository.
   - Edit local alias.
   - Toggle whether alias is shared.
   - Show path locally, truncated in the middle.
   - Keep raw paths local only.

3. `Sharing`
   - Toggle cards in `sharing.cards`.
   - Toggle redactions in `sharing.redactions`.
   - Include short privacy copy that says aggregate activity leaves the Mac, while paths, branches, commits, filenames, editor activity, and assistant attribution do not.

4. `Advanced`
   - Concise instructions for using an LLM to reason about Vibes settings, similar in spirit to the main-window helper copy.
   - Diagnostic information that is safe to show locally, such as config path, relay URL, device label, app version, last sync time, and enabled sharing cards.
   - Copyable diagnostic summary if useful, with secrets and raw local repo paths redacted.
   - Check for updates can stay in the app menu, not here, unless a later auto-update settings group is needed.

Use standard SwiftUI controls. Keep the visual language spare: warm Vibes tokens, light text weights, minimal separators, no decorative cards.

### Invite UI

Move all of `FriendsSection` out of Settings and reshape it as `InviteFriendView`.

Open it from:

- Main window header `Invite` button.
- Main window empty state action.
- Menu bar companion item `Invite a Friend...`.
- Incoming invite URL handling can continue to show the focused accept sheet.

Recommended presentation for v1: a sheet attached to the main window.

The invite flow is short and context-bound, so a sheet is appropriate:

- Primary action: `Create invite link`.
- Result area: generated link, Copy button, Share button using the macOS share sheet if straightforward.
- Secondary action: `Have an invite code?` text field and Accept button.
- Pending open invites: compact list with expiry and Revoke.

Future option: if invite management grows into a broader friend-management surface, graduate it to a dedicated `Friends` window or a main-window friends detail view. Do not put that future management UI back in Settings.

## Implementation Plan

### Phase 1: Introduce Native Settings Scene

- Add a `Settings` scene in `VibesApp`.
- Move the existing settings state out of `MainPanel.showSettings`.
- Replace the footer gear action with `openSettings()` using SwiftUI's `OpenSettingsAction`.
- Keep `Cmd-,` and `Vibes > Settings...` system-owned.
- Give the Settings window a stable compact size.

Acceptance:

- `Cmd-,` opens Settings.
- App menu Settings opens the same window.
- Footer gear opens the same Settings window.
- Closing Settings does not affect presence publishing or the main window.

### Phase 2: Split Settings Into Panes

- Extract reusable pane views from the current `SettingsView`.
- Keep `ReposSection`, but place it under a `Repositories` pane.
- Add `GeneralSettingsPane`.
- Add `SharingSettingsPane`.
- Replace the pasted-JSON `AdvancedSettingsSection` with an `AdvancedSettingsPane` for LLM guidance and local diagnostics only.
- Remove `FriendsSection` from Settings.

Acceptance:

- Settings contains no invite creation, invite acceptance, or pending invite list.
- Settings contains no pasted-JSON editor or LLM-generated config import path.
- All settings write through `AppModel` and the existing config store.
- Sharing controls map directly to `sharing.cards` and `sharing.redactions`.

### Phase 3: Build Invite Friend Sheet

- Rename/extract `FriendsSection` to `InviteFriendView`.
- Present it from a new `@State private var showInviteFriend = false` in the main window.
- Add an `Invite` button to the main window header.
- Add an `Invite a Friend...` item to `MenuBarExtra`.
- Reuse the same model methods: `createInvite`, `copyLatestInvite`, `acceptInvite`, `revokeInvite`.

Acceptance:

- Creating an invite works from the main window.
- Accepting a code works outside Settings.
- Pending invite revoke still works.
- No invite UI remains under Settings.

### Phase 4: Polish Native Mac Behavior

- Ensure the main window and Settings window can be open independently.
- Make Settings non-resizable unless a pane needs extra space.
- Keep keyboard focus sensible when opening invite and settings views.
- Add VoiceOver labels where icon-only controls remain.
- Keep button labels title-case for native commands, while preserving lowercase Vibes display copy where it is brand text.

Acceptance:

- `make client` passes.
- A screenshot shows the native Settings window.
- A screenshot shows the separate Invite Friend sheet.

## Suggested File Changes

- `client/Vibes/VibesApp.swift`
  - Add `Settings` scene.
  - Add menu bar `Invite a Friend...`.

- `client/Vibes/ContentView.swift`
  - Replace custom Settings sheet with `openSettings`.
  - Add main-window invite presentation.
  - Extract settings panes and invite view.

- `client/Vibes/AppModel.swift`
  - Add small helpers only if needed for editing identity, relay, sharing redactions, or device label.

- `docs/client-runbook.md`
  - Update the UI map once the implementation lands.

## Non-Goals

- No friend discovery.
- No broad social graph.
- No detailed friend management dashboard.
- No productivity analytics panel.
- No raw local data in invite UI or shared payloads.

## Open Questions

1. Should display name, handle, relay URL, and device label be editable in v1, or should General be mostly read-only until a dedicated account-editing slice?
2. Should invite code acceptance live in the same invite sheet as link creation, or should incoming invite code acceptance be a smaller separate sheet?
3. Should the pending invites list show accepted/revoked/expired invites briefly, or only open invites as `spec-v2.md` currently suggests?
