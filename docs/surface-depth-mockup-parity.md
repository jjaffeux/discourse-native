# Surface depth parity

Reference: `/Users/joffreyjaffeux/Code/discourse-native-mockups`, branch
`test-mobile-layout` at `847614e`, look A. The source is the "Solid surfaces"
block of `src/app.css` and the rules that override it, with the class names
that `src/App.tsx` puts on each surface. Checked on 2026-10-27.

The app used to be flat everywhere ([appearance](material-mockup-parity.md)).
Look A is not flat. Every surface stands up off the window's ground, or sits
in it, through three edges:

- a 1px inset **rim** (`--glass-rim`),
- a 1px **catch of light** along the top edge (`--glass-hi`),
- the **shadows** it casts (`--glass-shade` and the menus' pair).

There is no tint to see through, no blur layer and no sheen.

## Tokens

| Token | Dark | Light |
| --- | --- | --- |
| `--glass-rim` | white 7% | black 7% |
| `--glass-hi` | white 7% | white 80% |
| `--glass-shade` | black 24% | black 9% |

`DSurfaceEdges.of(depth, brightness)` in
`lib/src/ui/foundation/surface_depth.dart` holds these tokens and every
shadow built from them. Each `DSurfaceDepth` names the mockup selector it
reproduces. `test/surface_depth_test.dart` pins the table below value by value
in both brightnesses.

## Surfaces

| Mockup selector | Edges | Native surface |
| --- | --- | --- |
| `[data-panel]`, `.glass-sheet`, `.composer-panel` | rim, `inset 0 1px 0` light, `0 12px 40px` shade | `DSurfaceDepth.panel`. Phone page card (`ForumMobileSurface`), pushed page sheet (`DSheetVariant.page`) and the page under it (both `DSheetViewport` underlays in `main_content.dart`), desktop page panels (framed `DPageSurface`s in `main_content.dart`) and `WorkspacePanel`, which also holds the docked composer. |
| `[data-panel].is-sheet` | none | A phone page under a page sheet: `ForumMobileSurface(coveredBySheet: true)` leaves the depth to the sheet and its underlay. |
| `.phone-drawer__panel .side-nav` | rim only | `DSurfaceDepth.rim`, `ForumMobileSurface.sidebar`. A shadow here would be cut short by the rail over its edge. |
| `.menu-surface` | `inset 0 1px 0` light, `0 2px 6px` black 20% / 8%, `0 18px 44px` black 38% / 16% | `DSurfaceDepth.menu`. Every `DPopoverContent` (dropdown menus, selects, comboboxes, date and colour pickers, navigation menus), the phone's menu sheets (`DSheetVariant.menu` and `adaptiveMenu`), `DDialogContent` (the mockup's `[data-modal].menu-surface`) and `DHoverCardContent`. |
| `.menu-sheet` border | `1px solid var(--border)`, no bottom | A bottom menu sheet's edge now runs round its top and down both sides, not along the top only. The catch of light lies inside that edge, as CSS lays an inset shadow inside the border. |
| `.menu-sheet.is-full` | no border, `0 -8px 32px` black 22% | `DSurfaceDepth.fullSheet`. A menu sheet that runs behind the keyboard (`extendBehindKeyboard`), which is the phone composer. |
| `.toast` (inline), `.cm-tooltip-autocomplete` | `0 8px 24px` black 25% | `DSurfaceDepth.floating`. `DToast`, and the composer's suggestions through `DCommand(depth:)`. |
| `.home-box-place:not(.is-active)` | `inset 0 1px 0` white 6% / 90%, `0 1px 2px` black 14% / 6%, `0 4px 14px` black 12% / 6% | `DSurfaceDepth.place`, `DPlaceCard`. A chosen card lies flat behind its ring. |
| `.home-box-place:hover` | white 9% / 90%, `0 2px 4px` black 16% / 7%, `0 10px 24px` black 18% / 10%, 1px up | `DSurfaceDepth.placeHovered`. The shadows ease over 0.2s; the lift runs 0.25s on `cubic-bezier(.34, 1.56, .64, 1)`. Only where hover highlights show. |
| `.sum-box`, `.stat-well` | transparent border, rim, `inset 0 1px 1px` white at 1.4 x `--glass-hi`, `0 4px 16px` black 8% | `DSurfaceDepth.block`. The summary's sections and its headline stats. Their border goes transparent, and the rim is drawn inside it. |
| `.timeline-scrub` thumb | `0 2px 6px` black 30% | `DSurfaceDepth.thumb`, `DSlider(variant: timeline)`. Its 0.5px ring was already there. |
| `.dock-float [data-lifted]` | `0 8px 24px` black 35% | `DMobileDockReorder.shadow`, now a `DCastShadow`. |

## How it paints

A CSS blur length is twice the Gaussian's standard deviation. Flutter's
`BoxShadow` converts its `blurRadius` another way, which would draw every
shadow about a fifth softer and wider than the mockup's. `DCastShadow` keeps
the CSS length, and its painter blurs by `blur / 2`.

`castPainter` draws each shadow as a blurred rounded rectangle. That shape
is the renderer's analytic fast path: one draw, with no offscreen layer. A
CSS shadow never shows under its own box, so the painter clips the box out.
A translucent panel (the appearance opacity setting) therefore does not
darken.

`insetPainter` draws the catch of light and then the rim. These are painted
between the surface's fill and its content, where CSS paints an inset shadow.
A surface with a border passes its widths, so the light falls inside the
border and not under it. A blurred catch of light (`block` only) is drawn as
bands along the edges. A mask blur reruns over its path's bounds on every
frame, so a band costs much less than one path the size of the surface.

Nothing adds a blur layer, a `BackdropFilter` or a `saveLayer`.

## Not matched here

- The mockup rounds the phone page card's top corners to 31px under look A
  (`[data-touch] [data-panel-body].glass-sheet`). The page under a page sheet
  is rounded too (`.pushed-under`, 22px). Native keeps 22px on the card and
  square corners on the underlay. These are geometry, so the panel rim
  follows Native's corners.
- When a topic's head draws into its bar, the mockup drops the card's edge
  and shadow (`.glass-sheet:has(.topic-head-compact)`). This depends on the
  one-line topic head.
- The open search field merges into its menu (`.bar-field.is-merged`,
  `.menu-surface.is-attached`) with its own pulled-in shadows. Native has no
  merged field.
- Wells and tracks (`.glass-well`, `.glass-inset`) take an inset
  `--border-subtle` rim. Chosen bar items (`.bar-item.is-on`) take a lit top
  and a 1px shadow. Neither was audited against Native's chrome controls.
- Popovers keep their 0.5px outer ring, and dialogs keep their 1px ring. The
  mockup draws a 1px `--border` inside both.
- The theme swatch (`.glass-swatch`), arrival banners (`.arrival-banner`), the
  composer's selection bar (`.selection-bar`) and its block-drag ghost have no
  Native counterpart yet.

## Coverage

- `test/surface_depth_test.dart` pins every value above against the mockup in
  light and dark. It renders each wired surface onto a grey canvas and reads
  pixels for the rim, the catch of light inside a border, the shadow below or
  above, no shadow under a translucent fill, the sidebar's lack of one, and a
  place card's rise under a mouse. With the painters disabled, every pixel
  test fails. Each wiring choice (the sidebar's rim, the sheet's side edges,
  the writing sheet's missing edge) fails when reverted.
- `test/forum_mobile_surface_test.dart` now expects the page card's rim on its
  edge and its shadow on the ground round its corners.
- The four `controls-*-open.png` goldens show the menus' shadow.
