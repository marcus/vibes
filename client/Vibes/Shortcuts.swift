import SwiftUI

// Shortcuts — the single source of truth for every keyboard binding in Vibes.
//
// Keeping the bindings in one enum makes conflicts auditable at a glance and
// turns "add a shortcut" into a one-line change plus one wiring site. Each
// binding is wired through whichever SwiftUI mechanism matches its scope:
//   • app-global actions  → a Button in VibesApp's `.commands` block
//   • menu-bar mirrors     → `.keyboardShortcut(...)` on the MenuBarExtra item
//   • contextual dismissal → `.onExitCommand` on the focused view (ESC)
//
// ⌘, (open Settings) is intentionally absent: SwiftUI's `Settings` scene wires
// it automatically, so re-declaring it here would only risk a conflict.
enum Shortcuts {
  /// Open the "Invite a Friend" sheet.
  static let invite = KeyboardShortcut("i", modifiers: .command)

  /// Toggle the feed between the orbit sky and the list fallback.
  static let toggleFeed = KeyboardShortcut("l", modifiers: .command)

  /// Scan repos, publish status, and refetch the feed.
  static let scan = KeyboardShortcut("r", modifiers: .command)
}
