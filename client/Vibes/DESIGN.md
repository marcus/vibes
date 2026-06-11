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

## Window

The main window is **resizable** (`VibesApp.swift`): no
`.windowResizability(.contentSize)`, a `.defaultSize(460×620)` first-launch
frame, `.windowResizeAnchor(.topLeading)`, and a `minWidth 460 / minHeight 520`
floor on `ContentView`. The friend feed caps its card column at `maxWidth 640`
and centers it so cards don't stretch edge-to-edge on wide windows; the
`ScrollView` uses `.scrollEdgeEffectStyle(.soft, for: .all)` so content fades
under the header/footer instead of meeting a hard divider. The **Settings**
window stays fixed-size (`.windowResizability(.contentSize)`), standard for a
settings scene.

## Orbit view

The default main view (`OrbitView.swift`, design source: `design/mockups/`) is
deliberately playful, but stays inside the system palette wherever the color
has meaning:

- **Churn ring** — sweep is today vs the person's `typical_churn` (server
  median); the arc splits `.systemGreen` / `.systemRed` by adds-vs-deletes,
  matching the LOC color semantics above. Past 1× a `.yellow` lap badge
  appears.
- **Orb glow** — the avatar's own gradient color used as light (the existing
  user-chosen-color exception), falling back to the accent.
- **Repo moon dots** — a small decorative exception: each repo alias gets a
  stable hue derived from its name (djb2 hash) so repos keep their identity
  across machines. Dots only; text stays `.secondary` on `.quaternarySystemFill`.
- **Motion** — orb floating and ring animation are skipped under Reduce Motion.
  Layout uses fixed constellation slots (≤6 orbs) and a staggered grid beyond.
- **Empty sky** — with no friends, orbit still renders your own orb plus an
  invite nudge, so the header toggle always visibly switches views.

The list view (FriendCard column) remains available via the header switcher
and is the fallback only while the first feed hasn't loaded.

## Header / presence

The header row shares the traffic-light band (`ignoresSafeArea(.top)` +
58pt leading inset past the lights): the 17pt "vibes" wordmark, then the
floating controls — the orbit/list glass capsule, the one-dot
**PresenceLight** (green lit = online, at-rest = offline; click toggles),
and refresh. The menu-bar extra keeps explicit Online/Offline items as the
discoverable counterpart.

**Floating controls are Preview-style**: every glass control in the header
and footer shares one height (`FloatingControl.height`, 32pt) — circles for
single-icon buttons (presence, refresh, gear), capsule pills for grouped or
labeled ones (orbit/list toggle, Invite). Geometry is owned by the label
(`.buttonStyle(.plain)` + `.glassEffect(.regular.interactive(), in: ...)`)
so heights stay exact.

The footer's left corner stays **quiet**: nothing when sync is healthy, a
small red warning label when it isn't, transient success messages in between.
First-run nudges (a bobbing `OnboardingNudge` arrow) float above the gear
(no repos yet → the gear opens Settings on the Repositories tab) and then
above Invite (repos but no friends).

## Feed text size

`FeedTextSize` (Settings → General → Appearance, `@AppStorage "feedTextSize"`)
maps Standard/Large/Extra Large to `DynamicTypeSize` `.large/.xLarge/.xxLarge`
and is applied to the feed content only (status field, orbit, list) — never
the window chrome. The default is **Large**: one notch above system size for
readability. Fixed-size exceptions (LOC bar counts) deliberately don't scale.

## Sanctioned exceptions

The no-custom-color / no-fixed-size rules have a few deliberate, commented
exceptions in the source:

- The user's **avatar gradient** (`Color(hex:)` in `Models.swift`/`AppModel.swift`,
  rendered in `AvatarView`/Profile Icon settings) — a user-chosen brand color,
  not chrome. The small drop shadow on the gradient initial is kept for
  legibility over that gradient.
- A handful of **exact `.font(.system(size:))`** values where the glyph must fit
  a fixed shape (avatar initials, the LOC-bar counts) or is a deliberate display
  mark (the "vibes" wordmark). Everything else uses Dynamic-Type text styles.

There are **zero** custom `VibeColor` tokens and **zero** custom `ButtonStyle`
types in the target — controls use `.glass`/`.glassProminent`/`.bordered`/
`.borderedProminent`, and surfaces use the system fills in the color table above.
