# Forum themes — 2026-09-19

The forum Settings dialog combines the gallery study's section sidebar with the
studio study's side-by-side theme controls and preview. General displays the
forum identity; Appearance owns color mode, forum default, presets, and custom
palettes. Narrow layouts use the existing Select for section navigation and
stack the preview beneath the editor. Copy is limited to control labels,
sample topic content, and validation/error messages.

## Implementation

- Uses existing Native Dialog, Sidebar, Select, Toggle, Tabs, Input, Textarea,
  Card, Button and Alert components. No UI kit APIs or styles were extended.
- The preview mounts the production `TopicListRow`, including title, excerpt,
  author, unread marker, and bookmark/pin treatments, with two fictional topics.
  Preview actions are excluded from focus and ignore pointer input.
- All 13 reference palettes are included. Opposite brightness swaps text and
  background, matching the supplied HTML reference. Clover Dark's missing
  status colors use Neutral's values, as in the studies.
- Forum geometry is retained when resolving personal colors. Font and layout
  settings remain owned by the forum/application.
- Theme overrides and custom libraries are saved per canonical forum URL.
  Restoring the forum default retains the custom library and resumes the
  current server palette rather than a copied snapshot. Existing mode migration
  is unchanged.
- Presets apply immediately. Custom edits preview locally until Save theme.
  Save errors retain the previously applied palette. Custom themes can be
  updated, deleted, copied as versioned JSON, and imported with validation.
- Draft text, including temporarily invalid colors, survives switching between
  the wide and narrow layouts. The editor uses hex inputs with passive swatches;
  there is no new color-picker component.

## Verification

- Focused static analysis of all changed Dart files: no issues.
- Full analysis: one pre-existing informational lint in
  `test/content_route_test.dart` (`prefer_const_literals_to_create_immutables`),
  outside this change.
- 62 focused tests passed across forum settings, palette persistence, custom
  editor, site-theme integration, AppTheme and the control-style adoption guard.
  Import and draft-resize coverage are included.
- Model coverage includes all preset identities, JSON validation/round trips,
  brightness/geometry resolution, per-forum restart persistence, default
  restoration, damaged entries, write failure, and hydration/save ordering.
- Widget checks include real preview components, custom edits and save, invalid
  hex values, malformed/valid imports, and preserving partial input during a
  1400px → 390px resize. Existing 360×640, 200% text, RTL checks pass in both
  brightnesses. These are widget checks, not mobile-device tests.
- `flutter build macos --debug --no-pub --target tool/forum_settings_review_main.dart`
  passed. Native review used that existing in-memory fixture in an isolated
  `org.discourse.native.review.forumthemes` bundle. Ad-hoc debug signing retained
  sandbox/JIT/network and omitted restricted push identity; strict verification
  and actual launch succeeded.
- Native macOS inspection: sidebar sections; preset selection and app recoloring;
  dark/light mode; live accent editing; custom save; forum-default restoration;
  scrolling; Escape dismissal; and the final selection checkmarks and editor
  swatches. Both the original application renderer and shared controls appear
  in the preview. The isolated app was closed and desktop leases released.
- Installed Flutter 3.47.4 / Dart 3.13.3 were used. The repository SDK pin and
  lockfiles are unchanged. No external forum account changes were made.

## Mockup fidelity follow-up

The studio comparison restored the inset Light/Dark/System ToggleGroup, the
forum-default Card/Item with a trailing selected check, and a compact two-column
library of selectable Card/Items with miniature palette thumbnails. The preview
has the selected name and all seven live color swatches above a tinted studio
surface. It contains Native Search Input, Sidebar, topic filters, production
topic rows, New topic Button, and a Tracking Select with explicit footer padding
and the standard control gap. Sample text remains fictional. Long selected
palette names can wrap, and duplicate accessibility labels were removed.

Verification: 29 focused widget/integration/adoption checks passed, including
360px/200%/RTL, 390px draft preservation, all 13 thumbnails, seven preview swatches,
and actual rendered footer insets. Changed-file analysis and a macOS debug build
passed. Native inspection compared the studio HTML with the dialog in forum
default, Dracula dark and Shades of Blue light, including the custom editor,
sidebar/search preview, selection, mode switching and Escape dismissal. The
review used the same isolated fixture bundle described above; no kit APIs changed.

## Theme families and color modes

The library now has ten entries. Neutral combines the former Dark/Neutral
palettes; WCAG and Solarized each use their authored light and dark palettes.
Rose and Clover have mode-neutral display names. Legacy selected IDs map to
these families on load. Existing custom themes remain valid. The optional
alternate palette is included in the version-1 JSON representation when present,
with validation against repeated brightness and nested alternatives.

Thumbnails resolve against the active light/dark/system mode, matching the live
preview. Customization and Surprise me start from the requested palette mode.
Model checks cover exact WCAG/Solarized colors, legacy selection migration,
round trips, and thumbnail/preview color agreement in both modes.

## Window gradient and darker sidebars — 2026-09-19

Custom themes now include independent Window gradient and Darker sidebars
Native toggles. Both default to false for existing themes and travel through
version-1 JSON import/export, saved per-forum preferences, mode conversion and
authored alternate palettes. The root theme owns the options for both modes.

The window canvas blends Background into the derived selected color (20%
Accent). The title bar and instance rail expose the same canvas so the gradient
continues through desktop panel gaps. Content, cards and floating surfaces keep
their existing fills. The preview includes this window canvas around its card.

Darker sidebars applies a scoped Theme around the production forum/chat
navigation and preview Sidebar. Existing Native components supply every
control and interaction; no kit APIs were extended. Its background mixes the
current Background toward black (86% in light mode, 35% in dark mode). Text is
chosen against the brightest possible selected row to retain at least 4.5:1
contrast; accents try progressively lighter tints before falling back to text.
The content and shared panel tokens outside navigation remain unchanged.

Verification: 43 focused model/editor/AppTheme/shell-panel tests and 39
settings/integration/adoption tests passed. Coverage includes all ten preset
families in both modes with every combination of options, selected-row contrast,
legacy defaults, imports/exports, save/reopen, preview scope and restoring the
plain appearance. Static analysis passed with fatal infos. A macOS debug build
of the existing in-memory forum settings fixture passed. Native review in an
isolated `org.discourse.native.review.themeeffects` bundle verified both toggles,
live preview, saving and the applied light-content/dark-navigation shell with
its continuous outer gradient. A subsequent contrast refinement was covered by
the full preset matrix and rebuilt successfully.


## Appearance refinement — 2026-09-22

Font selection now uses Native Item rows with a sample in each bundled font,
a selected edge and a checkmark. The existing font preference and live forum
preview remain the source of truth. The existing Color mode control is the
only Light/Dark/System selector; no font-size control was added.

The user approved extending Native Color Picker and Slider for the supplied
reference. `DColorPicker.inline` is a dotted, persistent hue/lightness plane
with pointer input, arrow keys, adjustable semantics and Lighter/Darker actions.
`DSliderVariant.filled` adds a capsule and bar thumb while retaining the existing
controlled slider interaction. Both have runnable styleguide examples. The
application composes these with an exclusive vertical Toggle Group for Normal,
Lava lamp and Noise. Strength and chosen color update the preview immediately;
the strength control follows the chosen hue.

Optional `ForumBackground` settings travel through custom theme JSON, per-forum
storage, mode conversion and palette resolution. Legacy themes and gradients
retain their prior rendering until the new controls are used. The treatment
paints the existing window canvas (title bar, rail and panel gaps), with a larger
exposed canvas in the preview. Normal is a flat tint, Lava lamp uses moving soft
color fields, and Noise uses deterministic static grain. Only nonzero Lava lamp
animates; reduced motion and disabled ticker scopes stop it. Foreground panels
retain their existing surfaces.

Verification: 141 focused tests passed across the editor, model and persistence,
AppTheme, site appearance and app integration, color picker, all slider suites,
slider migrations, styleguide slider examples and control-style adoption. Added
coverage includes background export/storage/mode round trips, malformed options,
save/reopen, pointer and keyboard input, disabled/rejected palette edits,
standalone palette width, strength endpoints, and reduced motion. At 360px,
200% text and RTL, the custom editor was checked with macOS and iOS target-platform
overrides in both palettes; these are widget tests, not iOS device testing.
Static analysis and a macOS debug build passed.

Native macOS review used the in-memory forum settings fixture in isolated ad-hoc
review bundles, with restricted push identity omitted. Inspected font samples
and selection, custom palette dragging, strength, Lava lamp, Noise, save and
applied light/dark previews. Inspected the filled Slider styleguide and inline
Color Picker in full and 360px preview widths, including dragging and keyboard
input. The standalone review caught and fixed a loose-constraint width issue.
No external forum data or release configuration was changed.


## Background surface coverage correction — 2026-09-22

The custom background color now enters the resolved forum palette before Native
panel, sidebar, header, footer and control colors are derived. This corrects the
canvas-only tint that left the original theme showing across opaque surfaces.
The window canvas consumes the resolved color once; authored palette colors and
zero-strength behavior remain unchanged. Normal, Lava lamp and Noise share the
same resolved base, with the existing effects still painted on the window canvas.
Text and metadata contrast are re-evaluated for the tinted background.

Verification: 80 focused appearance, editor, model, AppTheme and site-palette
tests passed, plus a desktop app regression covering the painted title bar,
instance rail, sidebar, content card, footer and window canvas across both modes,
all three effects and the darker-sidebar option. The regression also restores
forum defaults. The color matrix checks text/metadata/selected-row contrast for
all preset families with white, black, pink and lime backgrounds, including
preservation of authored colors and exact zero-strength behavior. Static analysis
passed with no issues.

A macOS debug build and native review used a temporary in-memory fixture mounting
the production app with a populated topic list and a pink custom background.
Inspected the full shell, forum settings and the applied Light/Dark switch in an
isolated ad-hoc `org.discourse.native.review.backgroundsurfaces` bundle. Header,
rail, sidebar, topic list and footer all carry the chosen color. No external forum
data or release configuration changed.
