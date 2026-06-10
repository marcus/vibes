# Vibes — Design Rules (system semantics + Liquid Glass)

Vibes is a first-party-looking macOS 26 utility. There is **no custom design
system**. The old "Aurora II" / Teenage-Engineering color palette and the
custom flat button styles have been retired. When in doubt, use the stock macOS
component and let the system style it.

## Color

Use **semantic system colors only**. No custom hex, no `Color(red:green:blue:)`,
no appearance-aware `NSColor(name:)` palettes.

| Need | Use |
|---|---|
| Primary text | `Color.primary` / `.foregroundStyle(.primary)` |
| Secondary text (captions, last-seen, detail) | `.secondary` |
| Faintest text (timestamps, repo lists, extras) | `Color(nsColor: .tertiaryLabelColor)` |
| Accent / selected / primary action | system accent — `.tint` (user's accent color); never re-tinted to a brand color |
| Online presence | `Color(nsColor: .systemGreen)` |
| Errors | `Color.red` |
| LOC additions | `.systemGreen` text on `.systemGreen.opacity(0.15)` |
| LOC removals | `.systemRed` text on `.systemRed.opacity(0.12)` |
| Inset field / chip / quiet control fill | `Color(nsColor: .quaternarySystemFill)` |
| Card / raised content surface | `.background.secondary` fill |
| Hairlines, dividers | `Color(nsColor: .separatorColor)` / `Divider()` |
| The "me" card wash | subtle `.tint.opacity(0.12)` — keep it subtle |

Window and sheet backgrounds are the **system default** — do not paint a
full-bleed background fill. Let the window material show.

## Typography

Prefer Dynamic-Type text styles (`.title2`, `.headline`, `.body`, `.callout`,
`.caption`, etc.). Fixed `.font(.system(size:))` values survive only where exact
sizing is load-bearing for a tuned layout. **Keep monospaced digits** for LOC
counts and other numerics (`.monospacedDigit()` / `design: .monospaced`).

## Glass (control / navigation layer only)

Liquid Glass belongs to **floating controls and chrome**, never to content.

- Content (the friend feed, cards, rows, settings panes) sits on the standard
  window background with standard fills. **No `glassEffect` on cards.**
- Glass is applied deliberately and sparsely to the control layer — the presence
  toggle, footer action buttons, sheet/titlebar chrome — using
  `.buttonStyle(.glass)` / `.glassProminent`, `GlassEffectContainer`, and
  `.glassEffect(...)`. (Added in Phase 3 of the migration.)
- Never glass-on-glass. Don't tint glass decoratively; tint only for semantic
  meaning.
- Must remain legible under Reduce Transparency, Increase Contrast, and Reduce
  Motion.

## Out of scope here

The custom `ButtonStyle`s in `ContentView.swift` are still present pending the
Phase 3 controls pass; they have been reduced to system fills in the interim.
Window resizing, glass controls, and the grouped-`Form` settings conversion are
also Phase 3.
