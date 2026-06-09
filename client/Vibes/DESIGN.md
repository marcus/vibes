# Vibes — Design Tokens (Teenage-Engineering-derived)

Concrete, locked token set for the Vibes macOS app. The visual reference is
**Teenage Engineering's instruments** — OP-1, the Pocket Operators, the TX-6
mixer — *not* their marketing website, *not* skeuomorphism, *not* the
stereo/hi-fi/brass vocabulary.

What we borrow: **confident flat color fields, saturated accent pops against a
neutral/dark chassis, chunky rounded controls, pill buttons, segmented blocks,
dot indicators, and unambiguous on/off state.** Each control should read as a
real physical object you press. What we do *not* borrow: screws, brushed metal,
gradients-as-material, photoreal knobs, drop-shadow realism.

These tokens are the **single shared language** for both
- the **presence Online/Offline control**, and
- the **friend card**.

The toggle and the card pull from the same palette and shapes so they read as
parts of one instrument. Add new surfaces by composing these tokens rather than
inventing new colors.

---

## Color palette

All colors are defined in `VibeColor` (`client/Vibes/ContentView.swift`) and
follow the existing dark/light pattern: appearance-aware `NSColor` where a token
differs between modes, plain `Color` where it does not. Light = warm paper,
Dark = near-black ink — both warm, never clinical blue-gray.

### Foundations (existing — keep working)

| Token | Light | Dark | Use |
|---|---|---|---|
| `ink` | `#1A1714` (0.102, 0.090, 0.078) | — | Darkest warm base; text on paper, dark chassis source |
| `paper` | `#F2EEE6` (0.949, 0.933, 0.902) | — | Warm off-white base; app bg in light, text on dark |
| `background` | paper | ink | App canvas |
| `foreground` | ink | paper | Primary text |
| `muted` | `#6E6655` | `#A89F92` | Secondary text, captions, last-seen |
| `field` | ink @ 4.5% | paper @ 6% | Inset / input fill |
| `accent` | `#E05320` (0.878, 0.325, 0.122) | same | **Primary TE accent — burnt orange.** The "pop". |
| `accentForeground` | paper | paper | Text/glyphs on accent |
| `online` | `#2E8C57` (0.18, 0.55, 0.34) | same | Online-presence green dot |

### TE chassis & surfaces (new)

| Token | Light | Dark | Use |
|---|---|---|---|
| `chassis` | `#E4DECF` (0.894, 0.871, 0.812) | `#26221D` (0.149, 0.133, 0.114) | The neutral panel controls sit *on*. One step off `background` — the instrument body. |
| `cardSurface` | `#FBF8F2` (0.984, 0.973, 0.949) | `#302B25` (0.188, 0.169, 0.145) | Friend-card fill; reads as a raised block on the chassis. |
| `cardBorder` | ink @ 8% | paper @ 9% | Hairline edge defining a card/control block. |

### Accents (new)

| Token | Light | Dark | Use |
|---|---|---|---|
| `accent` (above) | `#E05320` | same | Primary — burnt orange. Default "lit" pop. |
| `accentSecondary` | `#2C6E91` (0.173, 0.431, 0.569) | `#3E8FB8` (0.243, 0.561, 0.722) | Secondary TE accent — petrol blue. For a second tactile category (e.g. a non-primary segment/indicator). Use sparingly; orange leads. |

### Control state language (new) — "lit" vs "at-rest"

Tactile controls have exactly two visual states:

- **lit** — the active / on / pressed-in state. Saturated accent field, high
  contrast. Online presence and any "engaged" control is *lit*.
- **at-rest** — the inactive / off / available state. Dimmed neutral, sits
  quietly on the chassis. Offline and any idle control is *at-rest*.

| Token | Light | Dark | Use |
|---|---|---|---|
| `controlLit` | `#E05320` (= `accent`) | same | Active control face. Saturated. |
| `controlLitForeground` | paper | paper | Glyph/label on a lit control. |
| `controlAtRest` | `#D8D1C0` (0.847, 0.820, 0.753) | `#3A342D` (0.227, 0.204, 0.176) | Inactive control face — neutral, recessed. |
| `controlAtRestForeground` | `#6E6655` (= `muted` light) | `#A89F92` (= `muted` dark) | Glyph/label on an at-rest control. |

Rule of thumb: a control is *lit* when it carries meaning (online, selected,
engaged) and *at-rest* otherwise. Never two-lit-states; the contrast between lit
and at-rest is the whole point.

---

## Shape tokens

TE instruments are chunky and rounded with crisp, generous radii — never sharp,
never fully circular except true indicators.

### Corner radii

| Name | Value | Use |
|---|---|---|
| `radiusControl` | `8` | Buttons, segments, small tactile blocks. Chunkier than the old `4`. |
| `radiusCard` | `14` | Friend cards, chassis panels. Generous, soft. |
| `radiusPill` | `999` (capsule) | Pill buttons, the Online/Offline switch track. |

### Control sizing

| Name | Value | Use |
|---|---|---|
| `controlHeight` | `34` | Standard tactile control / pill-button height. |
| `controlPaddingH` | `16` | Horizontal padding inside a control. |
| `controlPaddingV` | `9` | Vertical padding inside a control. |
| `segmentMinWidth` | `64` | Min width of one block in a segmented control (Online / Offline). |

### Indicators

| Name | Value | Use |
|---|---|---|
| `dotSize` | `10` | Presence dot (online green / at-rest neutral). True circle. |
| `dotSizeLarge` | `14` | Emphasized presence dot on a card header. |

### Card sizing (guidance, not hard tokens)

- Cards target a **comfortable** default width so several fit on screen; design
  the card to also render at a **denser** size (≈0.85×) past N friends.
- Internal padding: `16` comfortable, `12` dense.
- Inter-card gap: `12`.

---

## How the toggle and the card share this

- **Presence control**: track uses `radiusPill` + `controlHeight`. The active
  side is `controlLit` (orange) with `controlLitForeground`; the inactive side
  is `controlAtRest` with `controlAtRestForeground`. Online = lit, Offline =
  at-rest. Segments respect `segmentMinWidth`.
- **Friend card**: fill `cardSurface`, edge `cardBorder`, `radiusCard`. The
  online dot is `online` at `dotSizeLarge`; an offline/at-rest friend uses
  `controlAtRest` for the dot. Commit-count / repo chips are small at-rest blocks
  (`radiusControl`, `controlAtRest`) that go *lit* (`accent`) when emphasized.

Same colors, same radii, same state words on both — one instrument.
