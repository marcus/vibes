# macOS 26 + Liquid Glass Migration

**Status:** Mostly implemented (2026-08-21). Phases 0–3 and 5 are done:
deployment target is 26.0, Aurora II (`VibeColor`, custom button styles) is
fully retired, glass controls / resizable window / scroll edges are in, and
release plumbing emits `minimumSystemVersion` 26.0 with an SDK ≥ 26 preflight
check. The only open item is **Phase 4 (Icon Composer `.icon`)**, which this
plan itself marks deferrable — the app still ships the build-time generated
appiconset. Phase 6 verification was performed for shipped releases (0.10.x).
**Created:** 2026-06-10
**Targets:** `client/` (Vibes.xcodeproj), release scripts, appcast, web download page

## Goal

Move the Mac app to a macOS 26 (Tahoe) minimum deployment target and adopt the
system Liquid Glass design: default macOS semantic colors, standard control
styles, and glass where the system puts it. This **retires the custom
"Aurora II" design system** (the `VibeColor` palette, custom flat button
styles, TE-inspired chrome) in favor of stock macOS appearance. The app should
look like a first-party macOS 26 utility, not a themed app.

This is a redesign, not a reskin: most of the work is *deleting* custom
styling and letting the system take over, then applying glass deliberately in
the few places we have custom floating controls.

**What stays:** the information architecture and basic layout (header,
presence toggle, friend-card feed, footer; same settings panes), the SF
Symbols iconography, the avatar + presence-ring indicators (`AvatarView`'s
breathing ring), and the LOC add/remove visualization. Liquid Glass only
changes the chrome and control layer — content-layer elements like these are
fully compatible and keep their structure; only their *colors* move to system
semantics.

**What goes:** every custom color token, every custom `ButtonStyle`, custom
shadows/dividers/painted backgrounds, and the fixed-size window. Nothing
hand-styled survives unless a system equivalent genuinely doesn't exist.

**Window behavior change:** the main window becomes **resizable** (it is
fixed 460×620 today). The feed layout must adapt to width/height changes.

## Background / current state

- Project: `client/Vibes.xcodeproj`, pure SwiftUI, built with Xcode 26.5,
  `MACOSX_DEPLOYMENT_TARGET = 14.0`, Swift 5.0. No xcodegen/SPM manifest for
  the app itself; Sparkle 2.9.2+ via SPM.
- UI lives almost entirely in `client/Vibes/ContentView.swift` (~1,250 lines),
  plus `FriendCard.swift`, `AvatarView.swift`, `VibesApp.swift`,
  `UpdaterController.swift`.
- Custom design system "Aurora II": `VibeColor` enum at
  `ContentView.swift:1085–1196` (~28 appearance-aware custom color tokens),
  four custom `ButtonStyle`s at `ContentView.swift:1198–1239`, tokens
  documented in `client/Vibes/DESIGN.md`. No materials/vibrancy anywhere
  today — all flat fills.
- Scenes: fixed-size main `WindowGroup` (460×620), `Settings` window with a
  5-pane `TabView` (560×500), `MenuBarExtra`, two sheets
  (`InviteFriendView`, `InviteSheet`). No toolbars, sidebars, or split views.
- `#available(macOS 15.4, *)` guards around Apple Intelligence avatar
  generation in `AvatarGenerator.swift:47` and `AppModel.swift:440–508`.
- App icon: generated at build time by `scripts/generate-client-app-icon.sh`
  from `assets/icon.png` into `AppIcon.appiconset` (Xcode build phase
  "Generate App Icon", `project.pbxproj:141–172`). No Icon Composer `.icon`.
- Release: `scripts/release-mac.sh`, `scripts/generate-appcast.sh`,
  `scripts/preflight-release.sh`, `scripts/publish-mac-release.sh`,
  Makefile targets `client` / `mac-release` / `mac-publish`. Appcast at
  `release/appcast/appcast.xml` pins `<sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>`.
- Web download page already says "macOS 26" (commit 1897f4a), so the public
  requirement is ahead of the app — this plan brings the app in line.

## Key API facts (researched 2026-06-10)

- Building with the macOS 26 SDK (Xcode 26.x) is what activates the Liquid
  Glass appearance. We will also raise `MACOSX_DEPLOYMENT_TARGET` to **26.0**
  so new APIs can be used unconditionally (no `#available(macOS 26, *)`
  scattering). Do **not** add `UIDesignRequiresCompatibility` — that's the
  opt-out key and is slated for removal in Xcode 27.
- Core APIs (all macOS 26.0+):
  - `.glassEffect(_ glass: Glass = .regular, in shape: some Shape)` — default
    shape is a capsule. `Glass`: `.regular`, `.clear`, `.identity`,
    `.tint(_:)`, `.interactive()`.
  - `GlassEffectContainer { ... }` — wrap *multiple* nearby glass effects in
    one container (shared sampling, merge/morph, performance). Glass must
    never sample other glass: no glass-on-glass.
  - `.glassEffectID(_:in:)` / `.glassEffectUnion(id:namespace:)` for
    morph/merge between glass shapes.
  - `.buttonStyle(.glass)` and `.buttonStyle(.glassProminent)` — prefer these
    over hand-rolled `glassEffect` on buttons.
  - `.scrollEdgeEffectStyle(_:for:)` (`.automatic`/`.soft`/`.hard`) for
    content scrolling under bars; `.safeAreaBar(edge:...)` to register a
    custom bar for scroll-edge treatment.
  - `windowResizeAnchor(.topLeading)` (macOS-only) for animated resizes.
  - `backgroundExtensionEffect()` — N/A here (no sidebar).
  - `tabViewBottomAccessory` — iOS only, do not use.
- Free on recompile with standard components: glass sheets/popovers,
  redesigned standard controls (buttons, toggles, sliders, text fields, new
  metrics + morphing animations), glass titlebar treatment, updated
  list/form row metrics, scroll edge effects.
- HIG: glass belongs to the **control/navigation layer floating above
  content**. Content (the friend feed) stays on a standard window
  background. Don't tint glass decoratively; tint only for semantic meaning.
  Test Reduce Transparency / Increase Contrast / Reduce Motion.
- Sheets containing `Form`/`List` paint opaque over the glass — fix with
  `.scrollContentBackground(.hidden)` (+ `.containerBackground(.clear,
  for: .navigation)` if a NavigationStack is involved).
- Icon: Icon Composer (ships with Xcode 26) produces a single `.icon` bundle
  (background layer + up to ~4 foreground layers, per-layer translucency/
  specularity). Drag the `.icon` file into the project root (NOT the asset
  catalog), set build setting "App Icon name" (ASSETCATALOG_COMPILER_APPICON_NAME
  replacement / `App Icon` target setting) to the filename without extension.
  Xcode auto-generates a legacy `.icns` for older macOS embeds — irrelevant
  here since min OS is 26, but harmless.
- Versions as of today: macOS Tahoe 26.5.1 current, Xcode 26.5 latest stable.
  Build with Xcode 26.5.
- Primary references:
  - https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass
  - https://developer.apple.com/documentation/swiftui/glass
  - https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:)
  - WWDC25 session 323 "Build a SwiftUI app with the new design"
  - https://developer.apple.com/documentation/Xcode/creating-your-app-icon-using-icon-composer

## Design direction

Default macOS, full stop:

- **Colors:** semantic system colors only — `Color.primary`, `.secondary`,
  `Color(nsColor: .tertiaryLabelColor)` where needed, `.accentColor` /
  `.tint` left at system default (user's accent color), `.green` →
  `Color(nsColor: .systemGreen)` for presence, `.systemRed`-family for
  LOC removals, `.systemGreen` for additions. No custom hex values survive
  except where a brand mark genuinely requires it (none expected).
- **Typography:** system text styles (`.title2`, `.body`, `.caption`, etc.)
  instead of hard-coded `.system(size:)` where feasible; keep monospaced
  digits for LOC counts.
- **Controls:** standard `Button` with `.glass` / `.glassProminent` /
  `.borderless` / `.bordered` as appropriate; standard `Toggle`/segmented
  pickers; delete all four custom ButtonStyles.
- **Surfaces:** window uses the default system background (remove
  `VibeColor.background` fills). Friend cards become standard "content
  layer" surfaces: `RoundedRectangle` with
  `.fill(.background.secondary)` or `Color(nsColor: .quaternarySystemFill)`
  -style fills — *not* glass (cards are content, scrolling under controls).
- **Glass usage (deliberate, sparse):**
  - The presence toggle (Online/Offline capsule control) — the app's one
    true floating control → `GlassEffectContainer` + `.glassEffect(...)`
    or `.glassProminent` buttons.
  - Footer action buttons (Invite, etc.) → `.buttonStyle(.glass)`.
  - Header/footer treated as bars over the scrolling feed →
    `.safeAreaBar` + default scroll edge effect, or keep simple and rely on
    sheet/window defaults. Implementer judgment, but content must scroll
    *under* a soft edge, not hit a hard painted divider
    (`VibeColor.sectionDivider` goes away).

## Implementation phases

### Phase 0 — Preflight

1. Confirm toolchain: `xcodebuild -version` must report Xcode 26.x (26.5
   expected); `xcrun --show-sdk-version --sdk macosx` ≥ 26. If not, stop and
   report — everything else depends on this.
2. Branch: `macos-26-liquid-glass`. (The invite-sheet close button change is
   already committed on main as c3bcb14.)

### Phase 1 — Deployment target + recompile audit

1. In `project.pbxproj`, set `MACOSX_DEPLOYMENT_TARGET = 26.0` on all
   configurations (project + target level — search for every occurrence of
   `MACOSX_DEPLOYMENT_TARGET`). Set `SWIFT_VERSION = 6.0` only if it compiles
   cleanly; otherwise leave at 5.0 (out of scope).
2. Remove now-dead availability guards: `@available(macOS 15.4, *)` in
   `AvatarGenerator.swift:47` and the `#available(macOS 15.4, *)` checks +
   fallback paths in `AppModel.swift:440–508` (min OS now exceeds 15.4, so
   ImagePlayground availability is unconditional at compile time — keep any
   *runtime* model-availability checks, only delete the OS-version branches).
3. Build (`make client` or `xcodebuild -project client/Vibes.xcodeproj
   -scheme Vibes build`) and fix any deprecation errors/warnings introduced
   by the 26 SDK.
4. Run the app. Screenshot/record baseline: sheets, settings window, and
   menu bar already pick up some system changes for free. Note anything
   visually broken — this is the "recompile only" checkpoint.

### Phase 2 — Retire Aurora II (colors + typography)

This is the bulk of the diff. All in `client/Vibes/`.

1. Replace `VibeColor` usages with semantic equivalents. Mapping table
   (implementer applies case-by-case judgment but defaults to):

   | Aurora II token | Replacement |
   |---|---|
   | `background` | none — remove the fill; default window background |
   | `foreground` | `.primary` |
   | `muted` | `.secondary` |
   | `faint` | `Color(nsColor: .tertiaryLabelColor)` |
   | `accent` (burnt orange) | system accent (`.tint` default) — drop the orange |
   | `accentForeground` | `.white` via prominent button styles (automatic) |
   | `online` | `Color(nsColor: .systemGreen)` |
   | `field` | drop — standard `TextField` styling / `.quaternary` fills |
   | `chassis`, `cardSurface`, `cardBorder` | `.background.secondary` fill, `.separator`-based hairline stroke (or drop the stroke) |
   | `meCardSurface/meCardBorder` | same as card but `.tint.opacity(...)` wash or `.selection`-adjacent tint — keep subtle |
   | `locAddedBg/Ink` | `.systemGreen` text, `.systemGreen.opacity(0.15)` bg |
   | `locRemovedBg/Ink` | `.systemRed` text, `.systemRed.opacity(0.12)` bg |
   | `awayRowSurface` | `.quinary` / `Color(nsColor: .quaternarySystemFill)` |
   | `sectionDivider` | `Divider()` default or remove entirely |
   | `accentSecondary` | drop |
   | `controlLit/AtRest(+Foreground)` | replaced by glass/standard button states in Phase 3 |

2. Delete the `VibeColor` enum once no references remain
   (`ContentView.swift:1085–1196`).
3. Typography pass: convert `.font(.system(size: N, weight:))` to the nearest
   Dynamic-Type-aware text style where it doesn't break the fixed layouts;
   keep exact sizes where layout precision matters (the 460×620 window is
   fixed). Lowercase stylized headings ("invite a friend") may stay — copy
   style, not color, is in scope only where trivially adjacent.
4. Update `client/Vibes/DESIGN.md`: replace the Aurora II token tables with a
   short "we use system semantics + Liquid Glass" doc listing the few rules
   above (glass = control layer only, semantic colors only, no custom hex).
   Keep the file — it's read by agents.
5. Build + run + eyeball both light and dark mode at this checkpoint.

### Phase 3 — Controls & glass

1. Delete `AccentButtonStyle`, `PlainVibeButtonStyle`,
   `FooterTextButtonStyle`, `IconButtonStyle`
   (`ContentView.swift:1198–1239`). Replace usages:
   - Primary CTAs (copy invite link, accept invite, save) →
     `.buttonStyle(.glassProminent)`.
   - Secondary/footer buttons → `.buttonStyle(.glass)`.
   - Icon-only buttons (the new sheet close ✕, etc.) →
     `.buttonStyle(.glass)` with `Image(systemName:)` label; default capsule
     glass shape is correct.
   - In-form/settings buttons → `.bordered` / `.borderless` (standard, not
     glass — settings panes are content, and glass inside a Form is wrong).
2. **PresenceToggle** (`ContentView.swift:~724–760`): rebuild as a
   `GlassEffectContainer` containing the Online/Offline segmented control.
   Two implementations to try, in order: (a) plain `Picker` with
   `.pickerStyle(.segmented)` — if the macOS 26 default looks right, ship
   it; (b) custom two-button capsule using `.glassEffect(.regular.interactive())`
   on the container and `.glassEffect(.regular.tint(...))`/`glassEffectID`
   morph for the selected segment — tint only the *online* state, and only
   if the untinted default reads ambiguously. Prefer (a).
3. Friend feed scroll behavior: ensure the header and footer overlay the
   scrolling card list with the system scroll-edge effect (`.safeAreaBar`
   for the footer if it floats, `.scrollEdgeEffectStyle(.soft, for: .top)`
   if defaults don't kick in). Remove hard `sectionDivider` lines.
4. Cards (`FriendCard.swift`): system fills per Phase 2 table; bump corner
   radius to feel native next to glass capsules (system-concentric:
   use `.rect(corners: .concentric)`-style or keep 14–16pt — implementer
   eyeballs it). **No glassEffect on cards.**
5. Sheets (`InviteFriendView`, `InviteSheet`): remove any full-bleed
   `VibeColor.background` fill so the system glass sheet material shows. If
   either sheet gains a `Form`, add `.scrollContentBackground(.hidden)`.
6. **Settings window — full Liquid Glass treatment** (all six panes:
   General, Profile Icon, Repositories, Sharing, Advanced):
   - Convert each pane from plain VStacks to `Form` +
     `.formStyle(.grouped)` — this is what gives the stock macOS 26
     System-Settings look (grouped glass-adjacent sections, system row
     metrics, automatic section corner radii). The settings `TabView`
     toolbar picks up the glass treatment automatically on the 26 SDK.
   - `EditableSettingField`/`Field` become standard `TextField`s with
     default styling inside Form rows; `SettingsHeading` becomes Form
     `Section` headers (note: macOS 26 renders section headers in title
     case — drop any custom casing).
   - Add `.scrollContentBackground(.hidden)` only if a Form paints opaque
     over the window material; otherwise leave defaults alone.
   - Pane-level action buttons (e.g. regenerate avatar, add repository) →
     `.bordered`/`.borderedProminent` (standard in-form styles), not glass.
   - Remove any `VibeColor` fills behind panes so the system settings
     window material shows through.
   - Settings window may stay fixed-size (standard for settings), but
     recheck the 560×500 frame against the larger grouped-Form metrics and
     grow it if panes clip.
7. **Main window becomes resizable** (`VibesApp.swift`):
   - Remove `windowResizability(.contentSize)` from the main `WindowGroup`
     (keep it on Settings if Settings stays fixed).
   - Give `ContentView`/`MainPanel` `.frame(minWidth: 460, minHeight: 520)`
     and flexible max; the card feed (`LazyVStack` in a `ScrollView`)
     stretches full width with sensible padding — verify `FriendCard`,
     `AwayFriendRow`, and the empty state look right at wide and tall sizes
     (cards may want a `maxWidth` cap, e.g. ~640pt, centered).
   - Add `.windowResizeAnchor(.topLeading)` to the main window content.
   - Add `defaultSize(width: 460, height: 620)` so first launch matches
     today's proportions; the window remembers user resizes thereafter.
8. Avatar breathing ring (`AvatarView.swift`): keep — it reads well over
   glass. Switch ring colors to `.systemGreen`/`.secondary` per Phase 2.
   Verify `accessibilityReduceMotion` path still works.
9. **Custom-style sweep (exhaustive):** after the above, grep the client
   source for leftovers and remove every hit that isn't justified by a
   comment: `VibeColor`, `ButtonStyle(` (custom ones), `.shadow(`,
   `RoundedRectangle(cornerRadius:` with hard-coded fills,
   `Color(red:`/`NSColor(name:`, `.background(Color`,
   `.font(.system(size:`. The end state is zero custom color definitions
   and zero custom ButtonStyle types in the target.

### Phase 4 — App icon

1. Create a Liquid Glass icon with Icon Composer from the existing source art
   (`assets/icon.png` as the starting layer; ideally separate background and
   foreground glyph into layers — if the source is a flat PNG and no layered
   art exists, a single foreground layer on a solid/gradient background layer
   is acceptable v1). Save as `client/Vibes/AppIcon.icon` (check it into the
   repo — it's a folder-like bundle).
2. Project changes: add the `.icon` to the target; set the App Icon build
   setting to `AppIcon` (filename sans extension). Remove the "Generate App
   Icon" run-script build phase (`project.pbxproj:141–172`) and the now-stale
   `scripts/generate-client-app-icon.sh` invocation path; keep
   `assets/icon.png` as the web/source asset. Delete generated PNGs from
   `AppIcon.appiconset` (or the whole appiconset if nothing else references
   it).
3. Verify the icon renders in default/dark/clear/tinted modes (Icon Composer
   preview + Dock on a 26 machine).
4. Note: Icon Composer is a GUI app — if running headless/agent-only, this
   phase can be **deferred**: keep the existing build-phase icon (it still
   works, just renders in a system-provided rounded-rect "compatibility"
   treatment on 26) and file a follow-up. Do not block the release on it.

### Phase 5 — Release plumbing

1. `scripts/generate-appcast.sh` / appcast generation: minimum system version
   becomes **26.0**. Find where `sparkle:minimumSystemVersion` is sourced
   (generate_appcast flag or post-processing in the script) and update.
   There are no existing users, so no migration path is needed — old appcast
   entries can be regenerated/dropped freely.
2. `scripts/preflight-release.sh`: add a check that the build SDK is ≥ 26
   (e.g. `xcrun --show-sdk-version --sdk macosx`).
3. Grep `scripts/`, `Makefile`, `web/` for `14.0`/`macOS 14`/`Sonoma`
   strings and update to 26. The download page already says macOS 26
   (commit 1897f4a) — verify, don't double-edit.
4. Bump marketing version to 0.5.0 in the usual place(s) the release scripts
   read it (follow the 0.4.0 release commits as the template). **Do not run
   the release/publish targets** — that's a separate human-triggered step
   (signing credentials per memory: release flow is documented in
   `docs/plans/` + release scripts).

### Phase 6 — Verification

1. `xcodebuild ... build` clean with zero warnings introduced by this change.
2. Run the app on macOS 26 and verify, in **both light and dark mode**:
   - Window background is system default; no flat Aurora II paper/dark fills.
   - Presence toggle renders as glass, states clearly distinguishable,
     hover/press feedback works.
   - Footer/header buttons are glass capsules; feed scrolls under with soft
     edges; no glass-on-glass anywhere.
   - Both sheets show glass sheet material; close button works.
   - Settings panes look stock (grouped form), all fields still editable,
     avatar generation pane still functions, nothing clips at the settings
     window size.
   - Main window resizes smoothly: layout holds at minimum size, very wide,
     and very tall; presence ring, avatars, and LOC bars keep their layout;
     first launch opens at the default 460×620.
   - MenuBarExtra menu unaffected functionally.
3. Accessibility: System Settings → toggle Reduce Transparency, Increase
   Contrast, Reduce Motion — app must remain legible and functional in all.
4. Functional smoke test: invite flow round-trip, presence toggle actually
   publishes presence, Sparkle "Check for Updates" still works.
5. Screenshots of main window (light + dark), settings, invite sheet for
   review.

## Out of scope

- Any server/protocol changes.
- Swift 6 language-mode migration (only if free).
- Redesigning information architecture (same windows, same panes).
- Publishing the release (human-run `mac-release`/`mac-publish`).
- iOS/visionOS anything.

## Risks & notes

- **Resizable window is new surface area:** the layout has only ever been
  seen at 460×620. Budget verification time at min size, very wide, and
  very tall; cap card width rather than letting cards stretch edge-to-edge.
- **Bigger system control metrics:** macOS 26 standard controls are larger;
  the minimum window size and the settings window frame may both need to
  grow. Treat exact dimensions as adjustable during Phase 3.
- **`.glassProminent` uses the system accent color** (multicolor default) —
  the brand loses its burnt-orange identity. This is the explicit intent
  ("default mac colors"), but if it reads too generic, the sanctioned escape
  hatch is a single asset-catalog AccentColor, *not* re-tinting glass.
- **Segmented Picker vs custom glass toggle:** don't burn time on (b) if (a)
  looks fine. Timebox.
- **Icon Composer requires GUI** — Phase 4 is deferrable (see 4.4).
- No existing users, so no update-migration concerns; the appcast minimum
  simply becomes 26.0.
