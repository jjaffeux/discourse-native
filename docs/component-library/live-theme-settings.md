# Live theme settings

Forum Settings now opens Themes in the normal content page. The rail, sidebar,
open readers and other panels remain visible and update as fields change; the
separate theme preview and modal editor have been removed. Existing Back and
tab navigation own the page lifecycle.

The reference is `discourse-native-mockups` commit
`20dc23c3e7c97455225d0753b547a6ece0a173ae`, especially `App.tsx`'s
`appearanceFields`, `SCHEMES`, `ColorGrid`, `RampSlider`, `TextureSwitch` and
`BackgroundTexture`, plus the supplied September 23 Solarized screenshot.
The user explicitly approved adding the matching controls to Native.

## Form and appearance model

- The form is bounded to 588px inside 16px page insets. Sections use 12px
  outlined cards, 16px content padding and 18px spacing. Colour fields form
  three columns when space permits and reflow for narrow or enlarged text.
- Light and Dark select the live app mode. Each mode retains its own preset
  and six raw colours. Preset names and authored colours match all 13 reference
  schemes. Choosing a preset replaces only that mode's colours.
- Tint, opacity, texture and intensity are shared between modes. Accent tint
  reaches 22% for backgrounds and 11% for text, rounded to whole percentages
  as in the reference. Panel transparency is capped at 30%, frame transparency
  at 38%; fixed footers remain opaque. New effects start at 14% intensity.
- Native owns filled Input/Select surfaces, ramp Slider rendering, compact
  Color Picker rendering and equal-width icon-over-label Toggle tiles.
  Their original editing, focus, keyboard, disabled and semantic owners remain.
  The colour grid uses 80% HSL saturation and clamps lightness to 2–98%.
- A single window overlay uses the reference's 2D simplex grain and animated
  4D contour noise, including its frequency, opacity and overlay blend formulas.
  Flutter evaluates it in a fragment shader. A fixed permutation seed keeps
  rendering stable; it is not a byte-identical random texture to the browser.
  Reduced motion freezes lava. macOS supplies a native blurred backdrop behind
  transparent Flutter surfaces in both application profiles.
- Gradient restores the earlier lava effect as a fourth texture choice. It
  reuses the four moving radial gradients and 24-second loop, coloured by the
  live accent and controlled by Intensity. The live texture uses overlay
  blending to preserve text, remains visible at zero tint and full panel opacity,
  and freezes for reduced motion. Existing Lava lamp keeps the reference's
  contour texture; legacy background blending remains unchanged.
- Local preferences update synchronously; disk writes are serialized and
  coalesced during drags. A failed final write restores the last persisted
  palette and offers Retry. Effect changes preserve mounted form and reader
  state. Preferences are scoped to the selected forum.
- JSON remains version 1 with additive per-mode palettes and shared background
  fields. Legacy selected themes and exports retain their previous treatment
  until edited. Saved themes, import/export, fonts and reset remain available.
  Reset preserves the saved library and font while restoring forum colours.
- Copy theme works for the current pair of live palettes and individual saved
  themes. Shared theme cards retain their own small previews, independent of
  the settings editor. Undo after applying a shared card restores prior
  per-mode colours and effects while retaining the imported library item.
  A subsequent live edit supersedes the card's applied state.

The Native swatch popover offers HSV controls instead of the browser's platform
colour dialog. All six values also support hex input. Touch controls retain
Native target sizes, and the form reflows rather than shrinking those targets.

## Verification

Focused tests cover independent mode palettes, JSON round trips, forum-scoped
persistence, optimistic updates and failed saves, preset/hex/ramp/texture
interaction, import/export, font and reset, page routing, and retained form and
topic-reader state. Native component tests exercise keyboard and pointer
interaction, disabled controls, endpoints, RTL, both brightnesses, text scaling
and touch-platform geometry. These platform overrides are widget tests, not
device tests.

The macOS local-data fixture `tool/forum_settings_review_main.dart` was built
and launched as an isolated ad-hoc bundle using the permitted debug
entitlements. Native inspection covered the full-page forum menu entry,
Solarized light and dark, whole-workspace updates, noise and lava at increased
intensity, opacity, resized colour columns and ordinary navigation. No account
data or real settings were used. Earlier preview-only evidence is superseded
by this production-page review.

Runnable styleguide additions are Slider / Appearance ramps, Color Picker /
Compact colour grid, Toggle Group / Texture tiles, and Input and Select /
Filled form field. Root and full-profile static analysis pass. Focused commands
and the final integration result are recorded with the completed review below.

### Completed review — September 24, 2026

The implementation at `627e8a16d` was integrated with main's theme sharing at
`396a21039` in `b1b39a4ad`, preserving copied theme cards and their undo behavior.

- 216 tests passed across the theme model, settings controller, page, editor,
  appearance background, app integration, Native controls, input styleguide,
  control adoption and composer clipping suites. After integration, 73 tests
  passed across clipboard, sharing, onebox, settings, app and outline-pill tab
  suites. The onebox suite then passed all 7 tests, including a new regression
  for live edits superseding an applied shared theme. These runs overlap.
- `dart analyze` passed at the repository root and in `profiles/full`.
- `flutter build macos --debug --no-pub -t tool/forum_settings_review_main.dart`
  passed for the final integrated source.
- The actual macOS app was inspected in light and dark modes. The form retains
  typed text while switching textures and modes, and texture overlays allow
  pointer input. The Native styleguide's appearance ramps, compact colour grid,
  texture tiles and filled select were inspected; keyboard input advanced a
  ramp from 30% to 31%.
- A final launch of the integrated build confirmed Settings opens directly at
  the Themes heading without a redundant desktop Back row, Solarized updates
  the surrounding workspace, the form uses three colour columns at reference
  width, and Copy theme displays its success notification. The isolated review
  app was closed after inspection.

### Gradient follow-up — September 24, 2026

`6b437ef9a` adds Gradient beside None, Noise and Lava lamp. The texture tile
example includes the fourth choice. The original radial-gradient renderer is
shared with legacy themes; only live texture compositing uses overlay blending.

- 83 focused tests passed across gradient/noise rendering, appearance, editor,
  app, model, sharing and Toggle Group suites. The final rendering run covered
  intensity in both brightnesses, preservation of black/white foregrounds,
  reduced motion, a single nested-window effect and legacy noise behavior.
- Root and full-profile `dart analyze` passed. The macOS settings fixture built
  successfully. Native inspection confirmed all four tiles fit the 412px page,
  pointer and keyboard intensity changes work, the previous smooth animation
  appears across the window, and mode changes retain the choice and intensity.
  The final overlay blending was inspected at 100% intensity in both dark and
  light modes. Only isolated fixture data was used, and the review app was quit.

### Font preview restoration — September 24, 2026

The Font section again shows all four typefaces with their sample sentence,
using Native Item rows inside the current form card. Selection still updates
the workspace immediately. Each sample retains its own font and packaged
fallback, including the system font when another typeface is selected. Samples
wrap at narrow widths and enlarged text sizes.

- All 11 settings-page and theme-editor tests passed, including both palettes,
  macOS/iOS platform overrides, 360px width, 2× text and RTL.
- Root `dart analyze` and the macOS settings fixture build passed. Native
  inspection confirmed the four distinct samples, Lato and JetBrains Mono
  selection, and live workspace updates. Only isolated fixture data was used;
  the review app was quit afterward.

### Theme thumbnails — September 24, 2026

The preset dropdown is replaced by responsive Native Item thumbnail cards.
Saved themes appear first under Your themes, followed by Forum default and the
presets for the current mode. Saved themes remain available in both modes.
The existing miniature renderer uses each choice's colours with the current
shared background treatment. Selection updates the active mode immediately;
the Native outline marks selection without changing card height.

The user approved Native Item's hover-revealed corner action. Only saved themes
have a delete button; keyboard focus reveals it too, and touch/accessible
navigation keeps it visible. Native Alert Dialog names the theme and requires
Delete or Cancel; Escape cancels. Deletion preserves the current appearance,
font and other forums, and failed persistence retains the existing Retry flow.
Saved-theme copy actions remain in Save and share.

Focused verification covers ordering, thumbnails, selection in both modes,
stable card size, confirmation/cancel/Escape, active and inactive deletion,
persistence and forum isolation. Item tests cover independent pointer/keyboard
activation, retained semantics, directional corner placement and touch targets.
Narrow RTL layouts at 2× text are covered with macOS/iOS platform overrides.

- The final candidate `c8bde17ae` integrates current main `681c6d279`, preserving
  the latest Native control sizes and restored font samples. All 70 tests passed
  across Item, theme editor, settings page, appearance background, clipboard and
  app-theme integration suites. Root and full-profile `dart analyze` passed.
- The macOS settings fixture built successfully. Native inspection of the
  integrated build confirmed two-column cards at 412px, saved themes first,
  stable card height on selection, mode-specific thumbnails and live workspace
  changes in both light and dark modes. Item's Hover corner action example was
  inspected and its independent action incremented without selecting the card.
- Native Cancel and Delete flows were inspected on the preceding build with
  identical deletion behavior: Cancel preserved both saved cards; Delete removed
  only the named card and retained the active appearance. The final candidate
  only refined selection decoration and preservation of inactive preferences,
  both covered by the passing regression tests. Only seeded in-memory fixture
  themes were used; the isolated review app was quit after inspection.

### Remove Save and share — September 24, 2026

At the user's request, the entire Save and share accordion is removed, including
the saved-theme copy rows, name input and save/import/export/copy actions. The
unused editor callbacks, file-transfer code and clipboard helper are removed too.
Existing saved themes remain in the thumbnail picker with confirmed deletion;
live palette/background editing and font samples continue to work.

All 21 theme-editor, settings-page and appearance-background tests passed, and
root `dart analyze` reported no issues. Tests for the removed controls were
removed; the reset test now seeds an existing saved theme directly.
