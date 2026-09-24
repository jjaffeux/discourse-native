# Tabs reference and acceptance

Frozen catalogue date: **2026-09-08**.

## September 18 line-tab redesign

The user's localhost:5183 sidebar reference supersedes the original horizontal
line geometry below. Browser measurements: 13px labels, weight 600 selected / 400
inactive, 20px gaps, zero horizontal padding, 10px vertical padding, a 2px active
underline and a 1px full-width divider. The HTML row measured 41.5px high.

Native horizontal line tabs use the shared size typography (regular 13/20),
42px regular artwork and at least 48px touch height. Labels and composed badges
own the underline width. Inactive labels use `mutedForeground`; the active rule
uses `foreground`, and the divider uses `border`. They update from the current
palette. The rule paints inside the trigger, so scrolling cannot clip it.
Vertical line tabs and other variants retain their existing treatment.

The existing sidebar, Chat information, user summary and topic recommendation
consumers receive this change through `DTabListVariant.line`. The offline
`tool/sidebar_review_main.dart` fixture now includes a Line tabs preview and 32
unread Chat messages for comparison with the supplied reference.

Verification:
- 80 focused tests passed across Tabs, Tabs styleguide, sidebar panels, Chat
  channel information and user summary. Geometry, selected weight, scrolling underline pixels,
  touch, 200% text, RTL, keyboard navigation and sidebar switching are covered.
- Native macOS fixture inspected in light and dark, with Forum/Chat switching,
  the 32-message badge, and the actual Line styleguide example at regular size
  and 260px/200%/RTL. Enlarged Analytics selection moved the underline correctly.
  This is macOS review with simulated mobile metrics, not iOS device testing.
- Root static analysis passed. The isolated debug bundle was copied with
  framework symlinks preserved, signed without restricted identity/push
  entitlements, verified, launched and closed; project signing was unchanged.
- One broader recommendation integration case fails with a topic-header
  overflow and missing related-topic body. The same failure reproduces with
  the original Tabs implementation from `741b9a7c4`; the other case passes.
  Logs: `/tmp/tabs-recommendation-tests.log` and
  `/tmp/tabs-recommendation-baseline.log`.

## September 25 line-row height

The desktop line row's minimum was the regular control height plus 14px, which
gave 42px only while that preset was 28px. The September 23 design rules raised
it to 34px, inflating every desktop line row to 48px. Desktop rows are now the
label line with 11px above and below and no preset floor: 42px regular (the
reference's 41.5px with the text line rounded to whole pixels) and 43px for
Chat information's large tabs. Touch rows are unchanged. The regular default
list is 34px, its trigger 27px.

## Sources

- Frozen documentation: <https://ui.shadcn.com/docs/components/base/tabs.md>,
  SHA-256 `38d09f015f5856ced34f5af2449439611c845e952472c2382f2123d6fef2af0a`.
- Rendered documentation: <https://ui.shadcn.com/docs/components/base/tabs>.
- `base-nova` registry item:
  <https://ui.shadcn.com/r/styles/base-nova/tabs.json>, inspected
  2026-09-09, SHA-256
  `b4552a0329dd9a6e2bfaf03405c133874df5a4930c7bb3dd84c9ab5c45b89402`.
- Base UI behavior/API reference:
  <https://base-ui.com/react/components/tabs.md>, inspected 2026-09-09,
  SHA-256
  `c45845004593acab3c87dd79246f9591035fcbb0de16fdd990105c47a2d804aa`.

The frozen documentation hash was reproduced byte-for-byte before
implementation. Its covered sections are Usage, Composition, Line, Vertical,
Disabled, Icons, RTL, and API Reference.

## Source-to-Flutter mapping

| base-nova source | Flutter mapping |
| --- | --- |
| Root `flex gap-2`, horizontal roots become columns | `DTabs` uses an 8 logical-pixel gap, a column for horizontal tabs and a row for vertical tabs. At widths below 320px or text above 150%, vertical content stacks below its still-vertical list so neither side overflows. |
| List `w-fit`, `rounded-lg`, `p-[3px]`, horizontal `h-8`; default `bg-muted`; line `gap-1 bg-transparent rounded-none` | Intrinsic list, host `radius` (lg), 3px inset, 32px pointer height, muted default surface, transparent square line surface and 4px trigger gaps. A horizontal `SingleChildScrollView` keeps long/dynamic lists usable at narrow widths. |
| Trigger `h-[calc(100%-1px)]`, `px-1.5 py-0.5`, `rounded-md`, `text-sm/medium`, `gap-1.5` | 25px pointer trigger, 6px horizontal/1.5px vertical inset, `radius × .8`, 14/20 host-font medium text, inherited 16px icon theme and caller-composed 6px icon gap. Touch platforms retain at least 48px list interaction height around compact artwork. |
| Inactive `foreground/60`; hover/active foreground; disabled 50%; light active background; dark input/30 plus input border; active shadow-sm | Live `DTokens` foreground opacity, hover/selection, disabled opacity, background/input semantic mapping and small 1px-y shadow. No cached palette values. |
| Focus border plus 1px ring and 3px `ring/50` | Outside-only custom-painted 1px focus outline and 3px half-alpha host focus ring, avoiding interior tint. Pointer activation suppresses the ring while retaining focus; keyboard entry, navigation and activation restore it by default. |
| Line active pseudo-element: horizontal bottom -5px, 2px high; vertical right -4px, 2px wide | A 2px foreground rule paints 4px beyond the trigger. Vertical placement uses logical end, including RTL. |
| Horizontal overflow with the active line outside the trigger | Horizontal line lists reserve 6 logical pixels below the artwork inside the scrolling viewport. This keeps the rule visible when scrolling clips overflowing children, including enlarged text and touch targets. |
| Root value/defaultValue/onValueChange, List activateOnFocus/loopFocus, disabled fallback and missing fallback | Local `DTabs`, `DTabs.controlled`, borrowed `DTabController`, `DTabChangeReason`, manual/automatic activation, wrapping/non-wrapping roving focus, and dynamic disabled/missing reconciliation. Controlled values are never rewritten. |
| Arrow/Home/End navigation with disabled items skipped | Orientation-aware arrows, RTL horizontal direction, Home/End boundaries, Enter/Space manual activation, focus reveal in horizontal overflow. |
| Panel hidden by default; `keepMounted` opt-in | `DTabPanel` unmounts hidden child state by default. `maintainState` keeps it offstage with ticking and semantics disabled. Focus in a panel hidden by external selection returns to its matching trigger. |

## Acceptance criteria

- Public generic `DTabs<T>`, `DTabList<T>`, `DTabTrigger<T>`,
  `DTabPanel<T>`, `DTabController<T>`, variants and change reasons are exported
  from `package:discourse_native/discourse_ui.dart` without app dependencies.
- Every frozen example has an interactive styleguide entry using the final
  component, including the exact four-panel Card composition.
- Selection works in local, controlled and borrowed-controller forms. Dynamic
  reorder/removal/disable skips unavailable items and reports fallback reason.
- Pointer, semantic tap, Tab entry, arrow/Home/End roving focus, manual
  Enter/Space activation, automatic activation, disabled skipping and RTL are
  covered. Borrowed focus/scroll/selection resources are not disposed.
- Hidden panel lifecycle is explicit, retained panels do not tick or expose
  semantics, and focus does not disappear into a removed panel.
- Default/line geometry, live light/dark/custom tokens, host font/radius,
  reduced motion, 200% text, 260px layout and touch targets are covered.
- Group, Chat channel-info and Diagnostics top-level tabs use the generic
  renderer without moving routing, plugin, permission or data ownership.

## Adoption audit

Migrated:

- `lib/src/shell/topic_list_navigation.dart`: Recent/New/Top/Trending use
  controlled line tabs. The adapter groups New subsets and Top periods under
  their primary tab, keeps authentication visibility and feed routing, and
  composes the inline unread count with `DBadge`. Filters, New subnavigation
  and the Top period picker remain owned by the topic list.
- `lib/src/shell/message_inbox_page.dart`: Personal and group message folders
  use controlled line tabs. The message page keeps its identity across folder
  routes, and reading shortcuts defer to focused triggers so selection retains
  keyboard focus even when a message row is selected.
- `lib/src/shell/group_page.dart`: core and plugin primary tabs. The adapter
  retains capability filtering and translates selected generic values back to
  `GroupRoute`.
- `lib/src/plugins/chat/chat_channel_info_view.dart`: Settings/Members line
  tabs. The adapter retains channel/category labels and `ChatShellService`
  routing; the enclosing app bar remains 58px while the shared trigger keeps
  the measured 25px base-nova artwork.
- `lib/src/shell/diagnostics_panel.dart`: General, Topic scroll and dynamic
  plugin tabs. Capture/plugin state and callbacks remain diagnostics-owned.

Retained alternatives:

- `forum_tabs_bar.dart` and `aggregate_view.dart` are browser/workspace tabs,
  with close, reopen, reorder, persistence, drag feedback and context menus.
  They are not layered content tabs and remain application-owned.
- `topic_list_navigation.dart` retains the secondary New subset strip and
  Top period picker. `user_menu.dart` owns notification types, unread state
  and a vertical app rail; its renderer remains application-owned.
- Group secondary navigation and Preferences use sidebar/picker navigation,
  not the frozen Tabs composition.

## Prepared review surfaces

The ordinary styleguide target (`lib/styleguide_main.dart`) contains all seven
frozen example groups with local sample data. Existing focused test harnesses
mount the actual migrated Group, Chat and Diagnostics widgets with local/fake
data; no account or network mutation is required. The implementation task did
not acquire the shared desktop lease and therefore makes no browser/native
render claim. The independent reviewer owns official rendered comparison,
macOS inspection, any resulting fixes, final reconciliation, and merge.

## Message folder adoption follow-up — 2026-09-10

Message folders now use controlled line tabs. The follow-up also preserves
focus across folder routes, lets focused triggers own activation ahead of
reading shortcuts, and reserves the active rule's paint area inside the
horizontal scrolling viewport.

Verification:

- The final integration candidate based on main `6450ec59` passed all 140
  tests across `d_tabs_test.dart`, `message_inbox_page_test.dart`,
  `keyboard_navigation_test.dart`, `forum_workspace_test.dart`,
  `styleguide/tabs_examples_test.dart`, `chat_channel_info_view_test.dart`,
  `group_page_test.dart`, and `diagnostics_panel_test.dart`.
- `flutter analyze --no-pub` reported no issues; formatting and diff checks
  passed.
- Pixel regressions cover the scrolled active underline at 100% and 200% text
  on macOS and iOS target-platform overrides. The iOS checks are widget tests,
  not device testing.
- An isolated macOS bundle built from the code in `c6ed160d` mounted the real
  message page and styleguide with local data. Native inspection covered light
  and dark themes, a 360px viewport at 200% text, Personal and group folders,
  and the styleguide Line example. Arrow/End navigation, Enter/Space activation,
  retained focus after folder changes, group filtering and the visible scrolled
  underline were checked. Enter selected a folder even with a message row
  already selected.
- The final candidate preserves the inspected tab renderer, message adapter
  and keyboard ownership guard. Main's newer shortcut dispatcher is included
  in the combined integration test run above.

The isolated bundle launched with permitted debug entitlements; its source
and copied kernel matched SHA-256
`2407f7674fd7e8b6400b22f7377734fa9846b969cf5ff42e8093c8c2b3a6a22d`.
Earlier broader checks found three unrelated failures in group deletion and
topic reading; all three reproduced on unchanged baseline `a75a0e8e`.

## Topic feed adoption — 2026-09-11

Recent/New/Top/Trending now use `DTabs.controlled` and the line list through
`discourse_ui.dart`. New's unread count remains available to accessibility in
both layouts and uses `DBadge` when the inline toolbar displays it. The toolbar
lets the kit determine its content height, including touch targets and enlarged
text. Primary tabs keep their focus across feed and subset/period changes.

Verification:

- `flutter analyze --no-pub`: no issues.
- `flutter test --no-pub test/topic_list_navigation_test.dart test/d_tabs_test.dart
  test/keyboard_navigation_test.dart`: all 84 tests passed. Coverage includes
  primary/subset/period routing, signed-out tabs, unread semantics, filter
  preservation, narrow layouts, enlarged text, and keyboard focus/activation.
- The additional `shell_rebuild_isolation_test.dart` check has three existing
  failures: unrelated shell changes, pagination, and inactive-tab closure.
  Each was reproduced with the unchanged navigation source from base main
  `fbec1efa`; this adoption does not introduce them.
- An isolated macOS debug app (`org.discourse.topicfeedtabsreview`) mounted
  production `MainContent` with local fake feeds alongside the styleguide Line
  example. Inspected dark/wide and light/360px layouts at 100% and 200% text;
  exercised Top, New, Trending, arrow/Enter activation and End-key overflow
  reveal. The selected underline and focus outline remain visible when the
  focused tab scrolls into view. The app used local review entitlements without
  push/team identity and was closed after inspection. iOS coverage is through
  widget-test platform overrides, not an iOS device run.
- After integrating main `0642cfed`, static analysis remained clean and the
  same focused suites plus `test/topic_inbox_test.dart` passed all 157 tests.
  The Native tab renderer and inspected adoption source were unchanged by
  that integration.

## Default keyboard focus rings — 2026-09-11

All `DTabTrigger` variants now retain focus after mouse/touch activation without
painting the focus ring. Arrow/Home/End movement and Enter/Space activation
restore it, and leaving a trigger resets the pointer state so keyboard re-entry
shows focus normally. This is the component default; callers need no override.
The change stays within tab triggers and does not alter Flutter's application-wide
focus highlight strategy or the selected tab indicator.

Four rendered regressions cover default/line lists with mouse/touch input,
including clicking an already-focused tab, switching tabs, keyboard activation,
arrow movement and Tab/Shift+Tab re-entry. Both mouse cases reproduced the
unwanted ring before the change and passed afterward. Static analysis is clean;
all 171 tests in the Tabs, Tabs styleguide, topic navigation, message inbox,
keyboard navigation, Group, Chat channel info and Diagnostics suites pass.

Native verification used an isolated macOS debug fixture with production
`MainContent`, the styleguide Line example and a default-style tab list. Mouse
clicks showed no focus ring, keyboard navigation/activation showed the ring,
and clicking the focused tab hid it again. Checked dark/wide and light/360px
layouts at 100% and 200% text, including End/Enter scrolling to Trending. The
selected underline remained visible. The fixture used local fake data and was
closed after inspection; touch coverage is from widget tests, not a device run.

## Recommendation tabs adoption — 2026-09-11

The final application consumer of `ListNavigationTab` now uses controlled
`DTabs`, a line-style `DTabList`, and `DTabPanel` for recommendation content.
The retired widget and its import are removed. Source ordering, saved forum
selection, empty-source fallback, and topic-row navigation are preserved.

Verification:

- All 31 tab and recommendation-store tests passed, along with eight focused
  recommendation tests in the reading, inbox, and view-lifecycle suites.
- The reading integration test covers pointer selection, arrow/End focus,
  Enter/Space activation, content updates, and a 390px viewport at 200% text.
- `flutter analyze --no-pub` reported no issues.
- An isolated macOS app mounted the production reader with local data and the
  styleguide Line example. Both inbox and standard reader modes were inspected;
  light/dark themes, 340px/700px widths, and 100%/200% text were exercised.
  Native accessibility exposed individual tabs and recommendation content.
  Pointer selection, keyboard activation, and overflow reveal passed.

The initial review fixture called `ensureSemantics()` before macOS requested
accessibility. This left the native bridge with partial updates and caused
crashes during theme changes. The corrected fixture follows ordinary application
startup and lets the native accessibility request enable semantics. It exposed
the complete accessibility tree and passed the same theme/resize sequence.
No UI-kit or engine change was needed. Do not treat the earlier forced-startup
fixture crashes as a component regression.

## Inset and label alignment correction — 2026-09-11

The shared-size migration had given both the list and its triggers the full
control height and removed the list's vertical inset. Restore 3px list padding
and derive trigger minimum height as the shared height minus 7px (32/25 at the
regular size). Center composed trigger content so a plain label aligns with a
label-and-badge row. Vertical labels retain logical-start alignment. Selected
shadows use translucent black rather than foreground, which produced a glow
in dark themes.

Sizes remain minimums: compact sizes and enlarged/composed labels grow
intrinsically to preserve typography and the inset. Touch backgrounds account
for scaled label height, trigger padding/border and inset; interaction targets
remain at least 48px. No application-specific styling or new public API.

Verification: 72 focused Tabs, styleguide and topic-toolbar tests pass (the
final extra touch regression also passed in the 28-test Tabs suite), and static
analysis is clean. The downstream suites passed 114 tests with five failures;
all five reproduced with the unchanged renderer: three Group action-button
height expectations and two keyboard-navigation row-border expectations.

Read the current official base-nova registry and inspected the official dark
Tabs preview. An isolated ad-hoc-signed macOS fixture mounted production
MainContent with local feeds: inspected the dark wide New toolbar and clicked
Topics, confirming selection and centered labels. Narrow 200% light/dark
captures were partially obscured, so they are not claimed as full visual
verification; narrow/RTL/scaled geometry is covered by widget tests. The
fixture's permitted debug entitlements were read back; it and the reference
browser tab were closed. Final touch-only changes were verified with iOS
widget-test overrides, not a device run.

## Topic feed pill variant — September 16, 2026

The user supplied a topic-navigation screenshot and authorized adding
`DTabListVariant.pill` to the Native kit. Its transparent list uses 4px gaps,
muted inactive labels, semibold text, and a rounded selected fill at 8% semantic
foreground opacity. The shared control size and radius own the geometry;
selection paints immediately without a border, shadow or underline.

The topic-feed row uses the regular 28px preset and displays its existing New
count inline, without parentheses. Feed ordering, visibility, count calculation,
and the contextual New segments retain their existing behavior. The Tabs
styleguide includes an interactive Pill example matching the reference labels.
Keyboard navigation, touch targets, text scaling, RTL and horizontal overflow
remain owned by `DTabs`.

The production surface and styleguide can be inspected with the offline fixture:

```sh
flutter run -d macos --no-pub -t tool/topic_list_modes_review_main.dart
```

Verification:

- Root `flutter analyze --no-pub` passes, including the integration candidate
  based on `eea38056`. Formatting and `git diff --check` pass.
- 87 focused tests pass across Tabs, Document Tab, topic navigation, Tabs
  examples and control adoption. They cover immediate selection paint in both
  themes, keyboard focus, routes and counts, and narrow 200% RTL examples.
  The existing `feed select retains keyboard focus across routes (stacked:
  true)` failure also reproduces with the original topic-navigation source;
  it was excluded from the subsequent 87-test run.
- The offline macOS fixture built and ran in an isolated ad-hoc-signed bundle.
  Native inspection covered production topic tabs in light/dark, wide/390px,
  and 200% RTL, including New selection and its contextual segments. The actual
  dark Pill styleguide example accepted pointer selection and Right/Return
  activation with a visible keyboard focus ring. The app was quit afterward.
- Flutter-rendered light/dark reference strips used the system SFNS font and
  a 280×60 logical-pixel canvas at 2× pixel ratio. Mobile targets remain covered
  by widget tests; no mobile-device run was performed.
