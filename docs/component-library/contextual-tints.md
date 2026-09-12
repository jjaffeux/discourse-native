# Contextual tints

The user selected **D** from the [button proposals](../mockups/button-directions/README.md)
and approved extending the Native kit's shared control theme. This adopts the
selected direction across the app using each forum's resolved palette.
Implementation branch: `codex/contextual-tint-controls`, based on main `6c63feaf`.
Final integration branch: `codex/contextual-tint-controls-final`.
Merged into local main from the main checkout as
`15894fce62822fe227912a8af667037515bdf750`.

## Appearance and ownership

`AppTheme` supplies `DControlTheme` through `DTokens.controls`. The reusable
controls contain no dev.discourse.org swatches or site data. Neutral surfaces
use the forum background mixed with `primary-low`; their 1px border mixes
`primary-low-mid` into that background. Primary actions use `tertiary-low` with
readable accent ink. Tracking and Watching use a lighter accent tint and border.
Category triggers mix their actual category color into the same background.
Focus rings and links retain the forum accent instead of inheriting an action
fill. An inconsistent or missing `tertiary-low` falls back to a derived soft
fill so text stays readable through hover.

Button, Select, Toggle, Input, Input Group, Textarea and Combobox share these
control surfaces and radii. The regular control radius is 8px, as selected in
the proposal; other site geometry retains the forum's original radius. The
kit's 24/28/32/36px size scale and 48px native touch targets remain in effect.
Ordinary Material themes without the optional host theme retain the frozen
shadcn reference behavior. Its reference tests exercise that configuration.

Production adoption covers:

- Topic list category/tag filters and search: regular 32px neutral controls.
- Bottom navigation arrows: the same regular control height and inherited icons.
- Topic header category/browse group: the same geometry with category tints.
- Add tag: the neutral outline variant; existing tag editing keeps its behavior.
- Reply, bookmark and notification actions: regular size, with selected bookmark
  and active notification emphasis. The existing joined group owns shared edges.
- Topic progress: the existing `DButton` replaces the bespoke Material/InkWell
  rectangle and progress fill. Counts stay complete on one line, preserve their
  numeric order in RTL, and retain the existing navigation popup and focus owner.

The Button styleguide's Control consistency example shows all four sizes and
the contextual action group. Theme switching updates open overlays normally.

## Saved bookmark follow-up — 13 September 2026

The selected bookmark now retains its outline variant and shared divider.
Its fill, ink and hover come from the existing primary control tokens, matching
the mockup's selected tint without dropping the perimeter. This uses DButton's
existing color options; the app styling guard records this composition explicitly.
The bookmark trigger also declares its popup behavior, keeping it stationary
when pressed. No generic control API or geometry changed.

The topic bookmark and Tracking/Normal bell use the outline artwork from the
mockup's Lucide 1.17.0 source, including `bookmark-check` for the saved state and
the mockup's 1.8-unit stroke. Artwork lives in the existing DNativeIcons registry;
the generated Discourse icon catalogue remains intact. Reminder bookmarks retain
their clock indicator. Sources: [bookmark](https://raw.githubusercontent.com/lucide-icons/lucide/1.17.0/icons/bookmark.svg),
[bookmark-check](https://raw.githubusercontent.com/lucide-icons/lucide/1.17.0/icons/bookmark-check.svg),
[bell](https://raw.githubusercontent.com/lucide-icons/lucide/1.17.0/icons/bell.svg).
The retained [Lucide license](evidence/avatar/lucide-LICENSE.txt) applies.

Native verification used the actual topic action widgets in
`tool/contextual_controls_review_main.dart` with in-memory data and the saved
dev.discourse.org palettes. Checked selected/unselected states, Tracking/Normal,
dark/light palettes, 740px and 320px layouts, 100%/200% text, LTR/RTL, independent
hover, keyboard focus and Return activation, bookmark management and Escape
dismissal. Inspected the existing Control consistency example as well.
Only macOS was run; the compact checks were desktop fixture layouts.

The isolated `/tmp/bookmarked-controls-629a.app` launched successfully with the
permitted debug entitlements read back. Its kernel matched the build at SHA-256
`3c571b10efaf506328ee352c6b3e97b1ea1d7347b3e6aa075a097572858652b2`.
Static analysis passed. Focused checks cover saved-state transitions and hover
in both themes and footer widths, existing topic inbox interactions, bookmark
menus, icon rendering, contextual palettes and the explicit styling guard.

## Verification — 13 September 2026

Static analysis and formatting use the pinned Flutter 3.47.2 / Dart 3.13.2.
Focused coverage includes the changed primitives, theme/contrast, frozen Button
reference, joined controls, size/adoption guards, topic filters, search, taxonomy,
navigation, and progress lifecycle. New checks cover both saved dev palettes,
light/dark/forest/plum sample palettes, readable resting/hover ink, independent
focus rings, and live notification selection/theme changes.

`flutter analyze --no-pub` reports no issues. The focused run across 27 test
files reports **308 passes**, including all 12 updated golden images, and the
five pre-existing assertions described below. `git diff --check` is clean.

The first integration starts from main `c36adeb7` and merges the
implementation commit `3f39e730` without replacing the updated toolbar title.
The additional inbox/navigation run passes all **87 tests**, covering title
editing and scrolling, header/tag sizing, aligned footer heights at 100–200%
text, joined actions at 500px/2000px, bookmark/notification menus and Reply.

The final candidate starts from `36cd2d46`, preserving the subsequent inline
title editor. All **95 tests** in the combined inbox, title editor, field
ownership and contextual-theme run pass. Analysis is clean after integration.
The final macOS bundle was rebuilt and launched with the same Flutter kernel
as the candidate: SHA-256
`609a4680c32c7a1bb58f8917e96ee1cb2e00b987322efab3f657a1af45f60e63`.
Native checks repeated the combined dark header, editing and saving a title by
opening the category picker, typing into that picker, and the light 320px/200%
RTL action group. Counts retain `1 / 4` order. Both isolated review apps were
quit and the desktop lease was released.

The 12 control-family golden images were visually reviewed before updating:
light, dark, forest and plum at rest, hover and open; Flutter test renderer,
720×480, 100% text, repository JetBrains Mono and Material Icons. They are
regression baselines for the approved appearance, not native-device evidence.

The isolated macOS fixture `tool/contextual_controls_review_main.dart` mounts
the production filter/search/header/taxonomy controls, bookmark and notification
adapters, progress popup, and the actual styleguide comparison with in-memory
data. Native review covered the saved dev light/dark palettes and Plum, 740px
and 320px content widths, 100% and 200% text, LTR/RTL, hover, keyboard focus,
category/filter selection, tag search and saving, select changes, notification
selection, popup opening, Escape dismissal and focus restoration. Search remains
an independent native text field alongside the other AX controls. This was
macOS device review; mobile and other desktop platforms were widget-test
platform overrides, not device runs.

Build the fixture with `flutter build macos --debug --no-pub -t
tool/contextual_controls_review_main.dart --dart-define-from-file=DEFINES.json`.
The defines file contains `CONTEXTUAL_PALETTE` as a JSON string holding the
`appearance` object from the saved proposal palette. Without it the fixture
uses the ordinary app themes. Review bundles use an isolated bundle identifier
and the permitted debug entitlements in `tool/component_review/debug.entitlements`;
no production provisioning, account or release settings are changed.

Five existing assertions also fail unchanged on the starting main revision:
all four tab-trigger heights in `control_size_scale_test.dart` (the current
Tabs owner insets its triggers), and the old textarea inset expectation in
`d_textarea_test.dart`. They were reproduced in a separate clean worktree at
`6c63feaf`; this adoption does not change those layouts or their assertions.
