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
readable accent ink. Tracking and Watching use a lighter accent tint inside the
same neutral outline as adjacent controls.
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

Implemented in `34d7de00` and merged from the main checkout as
`40fc46b727488517392e409fb2f05a4c742f70d7`. The final candidate includes main's
tag-ordering changes; the reviewed topic actions, icons and control foundations
are unchanged from the native review. All 115 focused tests passed on that
candidate, and `dart analyze --fatal-infos` reported no issues.

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

## Meta palette follow-up — 13 September 2026

Implementation: `8206fb4a`, integrated with main `e7c4d6d2` on
`codex/meta-contextual-controls-final`. The reviewed notification controls,
theme, icons and styleguide are unchanged by that integration. All 162 focused
tests passed, including the 12 visual snapshots across four golden tests.
Static analysis passed. Merged from the main checkout as
`b2bf624f27f344a6465f0e757bb3ee813017e632`.

Meta's light purple accent made the notification half of the joined group look
heavier than its neutral bookmark. Active notifications now use the shared
neutral border in every palette. Their tint is 5% at rest and 10% on hover in
light mode, and 10%/18% in dark mode. Light-mode foregrounds mix less accent into
the forum text color, with contrast checked against both states. Primary actions
and the selected bookmark keep their existing fill and foreground tokens.
This is a theme rule for every forum; there is no Meta-specific production code.

Watching now uses an outline ringing bell, Muted an outline crossed bell, and
the labeled trigger the matching chevron. Topic, category, chat-thread and
styleguide notification menus use the same artwork family. These are existing
DIcon and DButton options, with no new component API. Additional Lucide 1.17.0
sources: [bell-ring](https://raw.githubusercontent.com/lucide-icons/lucide/1.17.0/icons/bell-ring.svg),
[bell-off](https://raw.githubusercontent.com/lucide-icons/lucide/1.17.0/icons/bell-off.svg),
[chevron-down](https://raw.githubusercontent.com/lucide-icons/lucide/1.17.0/icons/chevron-down.svg).

The regression palette [meta-palette.json](../mockups/button-directions/meta-palette.json)
contains only appearance values from the app's saved Meta instance. Both modes
join dev.discourse.org and the four styleguide palettes in contrast and shared
border checks. Widget tests switch an open joined notification menu from dev
dark to Meta light and verify its border, geometry, selection and dismissal.

Native macOS review used the real topic controls with both saved site palettes:
Meta Watching with and without a bookmark, Tracking and Muted, light/dark palette
switching, keyboard Home/End/Return selection and focus, and 320px RTL layout at
200% text. The dev light Control consistency example and dev dark topic actions
were also inspected. The matching kernel hash for the launched isolated
`/tmp/meta-controls-629a.app` and its build was
`3ec657e86133d9ce83a6fa846766b285e535a7da55723a4dfb34c10433108278`;
permitted debug entitlements were read back. No iOS or Linux device was run.
Category and chat-thread consumers were exercised by widget tests.

Reviewed the control renders at 720×480 with the bundled JetBrains Mono test
font: light/dark at rest, forest with a menu open, and plum on hover. Updated
the 12 visual baselines after that and the native review. A pre-existing
category toolbar ordering assertion
failed identically on main `551cb7a9` (872px versus an expected maximum 264px).
It now checks that the two controls do not overlap, allowing the current toolbar
order while preserving the menu interaction checks.

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
