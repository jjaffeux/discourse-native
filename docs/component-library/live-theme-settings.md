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
- Local preferences update synchronously; disk writes are serialized and
  coalesced during drags. A failed final write restores the last persisted
  palette and offers Retry. Effect changes preserve mounted form and reader
  state. Preferences are scoped to the selected forum.
- JSON remains version 1 with additive per-mode palettes and shared background
  fields. Legacy selected themes and exports retain their previous treatment
  until edited. Saved themes, import/export, fonts and reset remain available.
  Reset preserves the saved library and font while restoring forum colours.

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
