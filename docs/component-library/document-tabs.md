# Document tabs

The September 14, 2026 Codex screenshot reference replaces the forum strip's
page-connected selected tab and accent hover fill with independent rounded tabs.
The user explicitly authorized extending the Native library for this design.

`DDocumentTab`, exported with the Tabs family, owns a regular-size neutral surface,
shared control radius and typography, hover, selection gestures, drop outline,
and a separate small ghost close button. Selected tabs keep close visible;
inactive tabs reveal it on hover or keyboard focus without moving their labels.
The fill uses 6% of the semantic foreground over the host's canvas, retaining
neutral contrast in light and dark themes. Selection and hover paint immediately.

The forum adapter retains routing, shortcuts, context menus, rename state,
badges, overflow and drag/reorder behavior. It supplies selection semantics via
its existing tab wrapper, so `excludeSelectionSemantics` avoids an extra unnamed
selection button while retaining the close action. The strip has 8px gaps and
5px vertical insets; drag feedback uses the same Native tab. Ordinary content
`DTabs` default and line variants are unchanged.

The Tabs styleguide includes an interactive Document tabs example. Run the
production-adapter and styleguide fixture with:

```sh
flutter run -d macos -t tool/component_fixtures/document_tabs.dart --no-pub
```

Verification on September 14, 2026:

- Root `flutter analyze --no-pub`: no issues.
- 92 focused tests passed across `forum_tabs_bar_test.dart`, `d_tabs_test.dart`,
  `forum_tabs_platform_test.dart`, `forum_tabs_integration_test.dart`, and
  `control_style_adoption_test.dart`. This includes rounded-edge pixel samples,
  geometry, close visibility, rename, drag/reorder, shortcuts, menus, semantics,
  overflow, and desktop/mobile layout gates. Pixel comparisons quantize the
  composited color to the screenshot's 8-bit channels.
- Debug macOS fixture built and ran in an isolated ad-hoc-signed bundle with
  restricted push entitlement omitted; real project signing is unchanged.
  CUA inspected production tabs and the actual styleguide example in light and
  dark at the native window's 1144×768 screenshot size. Selection and closing
  were exercised; native accessibility showed distinct named close actions and
  the standalone example exposed separate selection and close buttons.
- The supplied Codex screenshots are the visual reference. No authenticated
  forum data was used. Other platform checks are widget tests, not device runs.

Follow-up: the user requested a transparent strip aligned after the forums rail.
The desktop sheet host now insets the bar by the shell's actual rail width while
keeping the sheet navigator's bounds unchanged. The shared bar no longer paints
a background. Integration tests assert its left edge at all desktop breakpoints;
pixel fixtures supply their own canvas beneath the transparent strip.

## Button selection correction — September 15, 2026

Document-tab selection now uses `DButton`, matching the existing close action.
The previous `InkWell` left Material's focus, press and splash painting enabled,
which could add a second bright rectangle over the tab's neutral surface.
The selection button is transparent in every state; the document tab owns the
shared selected/hover fill, and DButton owns the keyboard focus ring and control
interaction. Pointer-down selection, double-click rename, drag/reorder and
separate close actions remain supported.

Removed redundant label padding from the forum adapter, drag feedback and
styleguide. The minimum forum-tab width grows from 120px to 136px to accommodate
the button's standard padding while retaining three-digit unread badges.

Verification:

- `flutter analyze --no-pub`: no issues.
- 68 focused tests pass across Document Tab, Tabs, Forum Tabs Bar, platform
  layout gates, Tabs styleguide and control-adoption suites. Rendered light/dark
  regressions sample hover, press and release frames with conspicuous Material
  theme colors, then check keyboard selection and the separate close action.
  A regression also covers keyboard activation after dragging a tab.
- All 27 failures encountered in `forum_tabs_integration_test.dart` reproduce
  on unchanged source: its shell setup cannot find `InstanceSidebar`.
- An isolated macOS fixture mounted the production forum strip and Document
  tabs styleguide in light/dark, wide and narrow windows. Mouse selection keeps
  one neutral surface. Platform overrides and enlarged/RTL layouts are widget
  tests, not mobile device verification.

## Content sizing — September 19, 2026

Forum tabs now use their intrinsic content width, capped at the existing 160px
maximum. Short labels no longer stretch to an equal share or a fixed minimum;
icons, emoji, badges and custom label decorations participate in layout. Long
labels retain ellipsis, and the strip scrolls when its tabs exceed the viewport.
Document tabs use the small Native selection-button preset (8px horizontal
insets) and 2px outer insets. Close targets remain 24px, and drag feedback uses
the rendered tab width.

Verification: static analysis passes; 71 focused checks pass, including the new
content-width, custom-suffix, padding and maximum-width regression. Five existing
Forum Tabs Bar failures (two pixel samples, switcher hover color and two scaled
switcher rows) reproduce on unchanged main.

## HTML reference styling — September 19, 2026

The user authorized updating `DDocumentTab` to match the document strip at
`http://localhost:5183/`. The selected tab now has an 8px radius, a raised fill
and a 1px outline. Colors use the reference's palette formulas: foreground
mixed into the canvas at 10% for the fill, 22% for the border, 90% for selected
text and 50% for inactive text and close icons. Inactive tabs stay transparent;
hover retains immediate neutral paint, and the selected close action remains
visible. These rules supersede the September 14 paint and radius description.

The separately requested compact sizing remains: 28px shared regular height,
content width capped at 160px, small Native selection and close buttons, and
2px total outer horizontal inset including the border. A transparent inactive
border reserves the same space so selection never moves the label or close
button. The host's real icons, badges, menus, rename and drag handling remain.
The HTML's 35.5px height and 170px maximum are intentionally adapted to the
user's compact Native sizing. No application control is replaced.

Verification:

- Inspected the live HTML selected and inactive tabs and their computed palette
  values. A local macOS fixture mounted the production `ForumTabsBar` and actual
  Document tabs styleguide in light/dark and wide/narrow windows. Selection,
  close, add and visible keyboard focus passed. The isolated debug bundle used
  the existing local review entitlements, read back after signing; no release
  configuration changed. No mobile-device run was performed.
- `flutter analyze --no-pub`: no issues.
- 73 focused checks pass across Document Tab, Forum Tabs Bar, Tabs, Tabs examples,
  platform layout gates and control adoption. Rendered tests cover immediate
  hover/press/release paint, border and radius, stable selection geometry,
  keyboard activation and closing. Adapter checks cover rename, drag, overflow,
  content sizing, decorations and semantics.
- Five failures reproduced before the change on `eabd4a57a`: two obsolete tab
  pixel expectations, switcher hover paint and two 200% switcher-row heights.
  The tab paint checks now match the reference; the three unchanged switcher
  checks remain excluded from the passing focused run.

## Label typography — September 25, 2026

Tab labels use the 13/19.5 control role (`labelLarge` at weight 400), as
`docs/design/reference-rules.md` specifies for tab labels and the desktop tab
strip. The September 23 typography pass remapped `labelMedium` to 12.5 without
revisiting the strip, and the small selection button's own 12.5 text style
shadowed the tab's regular-size default. `DDocumentTab` now applies its label
style inside that button, so the forum adapter, its drag feedback and the
styleguide render labels at the same size. `workspaceTabStripHeightFor` grows
with the same role. The tab switcher keeps its 14px `bodyMedium` rows, matching
the reference's switcher list.

## Corner radius — September 25, 2026

The September 23 fixed Native radius scale (see `conventions.md`) supersedes
the September 19 8px selected radius: inactive tabs, including their hover
fill, use the pill radius and the selected tab uses the 14px panel radius,
independently of the site radius. `d_document_tab_test.dart` pins both.
