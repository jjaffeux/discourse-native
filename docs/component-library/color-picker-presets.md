# Color picker presets

The September 23 composer selection menu adds the user-approved preset and
recent-color extension to the Native color-picker family. The supplied composer
screenshots are the reference for grouping; Native Button and Dropdown Menu own
control geometry, focus, hover, touch targets and popup placement.

`DColorPickerPresets` accepts named `DColorPreset` values, an optional selected
value, controlled recent choices, an optional reset callback and a nullable
change callback. A null selection denotes the default color. Presets can display
a colored letter or a filled background swatch; recent choices may mix both.
The caller owns recent ordering and persistence. The existing continuous
`DColorPicker` and `DColorPicker.inline` APIs are unchanged.

The **Presets and recent colors** styleguide example exercises choice, reset and
recent history. The composer adapter keeps five recent choices for the lifetime
of its controller, emits `[color=#rrggbb]` / `[bgcolor=#rrggbb]`, and exposes the
palette only after the site's authenticated application document identifies the
`discourse-bbcode-color` plugin. Selecting a swatch preserves the selection and
participates in composer undo. Default removes only that color type; Clear
formatting removes inline wrappers while retaining unselected formatting.

Popup contents explicitly join the editor's `TextFieldTapRegion`, including
nested palettes and menus. This prevents desktop mouse presses from triggering
the editor's outside-tap unfocus behavior.

Verification uses focused composer formatting, keyboard/accessibility, mouse,
color picker, forum theme editor, site bootstrap and highlighting tests, plus
static analysis. `tool/composer_selection_review_main.dart` provides an offline
macOS fixture with light/dark, narrow/wide and the actual styleguide example.
The iOS density, 320px viewport, 200% text and RTL layout are widget-tested;
native device testing is limited to macOS.

Final verification: 245 focused tests passed; static analysis and the macOS debug
build passed. The isolated native fixture was inspected in light/dark and
wide/narrow layouts, including mouse selection, opening the palette, choosing
text/background colors, retained selection and recent choices. The actual
styleguide preset example was also rendered and its recent-choice behavior
exercised. The review app was closed and the desktop lease released afterward.

Broader checks found existing failures in the Markdown heading/font-size tests
and the details-upload deletion test; each was reproduced against unmodified
HEAD during this task. These unrelated failures are outside the focused passing
set above.
