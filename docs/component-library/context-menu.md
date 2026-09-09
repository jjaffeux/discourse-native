# Context Menu acceptance evidence

Prepared on 2026-09-09 from the frozen 2026-09-08 Base UI/base-nova
reference.

## Reference integrity

- Documentation: `https://ui.shadcn.com/docs/components/base/context-menu`
- Frozen Markdown: `https://ui.shadcn.com/docs/components/base/context-menu.md`
- Frozen Markdown SHA256 reproduced byte-for-byte:
  `ec20bd0ef47abb75872c1294d1563f0f279d3da5861177d8f2c588d8eb5f6895`
- Registry source:
  `https://ui.shadcn.com/r/styles/base-nova/context-menu.json`
- Registry SHA256 observed on 2026-09-09:
  `57bfdd236a7f4cb83625edf4c33265ce009738947666d00311034a88f6868756`
- Base UI behavior API:
  `https://base-ui.com/react/components/context-menu.md`

The frozen page defines Composition, Basic, Submenu, Shortcuts, Groups,
Icons, Checkboxes, Radio, Destructive, Sides and RTL. All ten runnable example
groups are registered. Installation, Usage and Composition are recorded in the
styleguide notes and public API.

## Reference-to-Flutter mapping

| base-nova source | Flutter mapping |
| --- | --- |
| Trigger `select-none`, secondary click and long press | `DContextMenuTrigger` preserves its child and owns secondary-pointer-down, touch long-press-start, Context Menu, Shift+F10 and accessibility long-press activation |
| Root `disabled`, controlled/uncontrolled open | `DContextMenu` forwards typed open/controller/change ownership to the shared Dropdown Menu/Popover lifecycle and forces closed while disabled |
| Virtual pointer anchor | A Context Menu-owned 1px `DPopoverAnchor` tracks the exact trigger-local invocation point; keyboard opens at logical bottom-start |
| Popup `min-w-36`, `p-1` | 144px minimum/default width and 4px shared menu padding |
| Popup `rounded-lg bg-popover text-popover-foreground` | live `DTokens.radius × 1`, `surface` and `foreground` through the shared menu owner |
| Popup `shadow-md ring-1 ring-foreground/10` | shared `DPopoverContent` medium shadow and translucent foreground ring |
| Root defaults `side=right`, `align=start`, `alignOffset=4`, `sideOffset=0` | `DContextMenuContent` forwards the same values to collision-aware `DPopover` positioning |
| Item `gap-1.5 px-1.5 py-1 text-sm rounded-md` | shared 6px gap/padding, 4px vertical padding, 14/20 host text and `radius × .8`; iOS/Android keep an invisible 48px row bound |
| Label, inset, separator, shortcut and icon slots | exact shared Dropdown Menu primitives: 12/16 medium muted label, logical 28px inset, 1px border rule, tracked muted shortcut and 16px caller icon slots |
| Checkbox/radio trailing check | controlled radio and controlled/default-owned checkbox wrappers retain the open menu by default and expose native checked semantics |
| Destructive focus | shared destructive foreground and multiplied 10% light / 20% dark focused fill |
| Submenu inline-end and directional arrows | shared sibling ownership, hover/arrow opening, logical RTL direction, typeahead/roving focus and deepest Escape |
| 100ms fade/zoom/8px slide | shared Popover animation, removed when reduced motion is requested |

Context Menu does not implement a second menu engine. It uses the accepted
Dropdown Menu owner for common menu content, navigation, selection and focus.
Shared-owner follow-ups must be accepted on main before this dependent merges.

## Acceptance criteria

- Public composition covers Root, Trigger, Content, Group, Label, Item,
  CheckboxItem, RadioGroup/RadioItem, Separator, Shortcut and nested Sub.
- Secondary pointer opens at its location; long press adapts to touch; Context
  Menu, Shift+F10 and the accessibility action open at logical bottom-start.
- Disabled root/trigger ignores invocation. Controlled/uncontrolled open state,
  borrowed controllers/focus, callbacks and restoration retain shared lifecycle
  rules.
- Roving arrows/Home/End, repeating typeahead, Enter/Space selection, nested
  inline direction, sibling ownership, deepest Escape, outside dismissal and
  Tab behavior come only from the final Dropdown Menu owner.
- Positioning supports top/right/bottom/left/inline-end, live edge collision,
  safe-area boundaries, scrolling, lifecycle cleanup and the moving pointer
  anchor.
- Live host palette/font/radius/direction/text scale and reduced motion reach
  open overlays. Native semantics expose enabled, checked/radio and expanded
  states with compact desktop and 48px touch rows.
- Basic, Submenu, Shortcuts, Groups, Icons, Checkboxes, Radio, Destructive,
  Sides and RTL are interactive styleguide examples using the real component.
- The forum rail's existing context-only Instance Actions adopts the component
  without losing its touch-sheet adaptation, permission guards, destructive
  confirmation, keyboard/reader entry, focus or controller/session safety.

## Application audit

`InstanceActions` is the direct product adoption. It already exposed the same
forum actions from secondary click, long press, Shift+F10 and a custom reader
action. It now uses `DContextMenu`, maps move/remove actions to the shared item
primitives, preserves the touch-only More Options sheet and retains its
custom-gesture adapter through `DContextMenuTriggerController`.

Chat message actions remain an explicit retained alternative. Their context
invocation opens a rich adaptive sheet with dynamic permission, pin/restore/
rebake busy state, flag subflows, bookmarks and per-message session guards; a
separate visible hover menu owns the compact subset. Replacing both with one
generic action tree without an adapter and native regression would erase those
differences. Editable composer/post selection context menus remain Flutter text
selection owners. Sidebar secondary navigation callbacks are direct alternate
navigation actions, not action menus. Specialized Choice/Command/category/tag
anchors and ordinary toolbar dropdowns are Dropdown Menu/adaptor concerns, not
context invocation migrations.

## Accepted dependency

- Parent: Dropdown Menu
- Reviewer: `01a085cf-f401-7813-80da-7c687de8a5d5`
- Accepted review branch: `codex/review-dropdown-menu-accepted`
- Accepted local-main merge: `5c6ab6a15d69c7241ab7d9345eb9f6d6418e2787`
- Progress follow-up: `a5ad2b5883e7b16e1ef3535f8836b5a86581c2bd`
- Parent evidence: 48 focused Dropdown/Popover/Table/styleguide tests pass
  with seed `826145`; root and `profiles/full` analysis are clean. Official
  rendered and native acceptance covered light/dark composition,
  keyboard/typeahead, checkbox/radio retention, submenu/Escape focus, RTL,
  scaling, lifecycle dismissal and the production Table actions.

The parent API has no public virtual-pointer anchor. Context Menu therefore
keeps the 1px point-anchor adaptation locally while reusing all common menu
content/navigation/selection. No shared parent API was changed. The final
Context Menu candidate is based on the accepted parent revision without local
changes to the Dropdown Menu source.

## Independent rendered and native review

Reviewer `01a0861f-38ca-7122-b18f-5f286ab90ccb` preserved the
implementation/handoff history on `codex/review-context-menu`, then prepared
new candidates from accepted current main without merging main into a worktree.
The initial prepared-parent source was source-equivalent to the subsequently
accepted Dropdown Menu implementation; its completed behavior checks remain
valid for that unchanged source.

The initial isolated styleguide bundle had kernel SHA256
`b26f476a523afa6d28849f22b3049719ea3ba50bc9055d021e1557a02fe05342`.
Live official reference inspection in light and dark confirmed 14/20 text,
28px rows, 6px gaps, 4px popup padding, 8px item radius, 10px popup radius,
1px translucent ring and medium shadow. The native app demonstrated:

- Secondary-pointer placement, selection callback and dismissal.
- Context Menu key entry, first enabled focus, disabled-item semantics,
  End plus submenu arrow navigation, deepest Escape and outside dismissal.
- Checkbox/radio checked semantics with retained open state, live Forest
  tokens, and a collision-safe 360px/200%-text/reduced-motion RTL submenu.

Two locked-Mac attempts were stopped and their leases released. After the user
unlocked the Mac, the remaining inspection completed on 2026-09-09 using
`tool/context_menu_review_main.dart`. This fixture mounts the production
`InstanceRail` and real Context Menu examples with only in-memory Alpha/Beta/
Gamma forums. It cannot change real accounts. It was rebuilt after accepted
Alert Dialog reconciliation at source
`0792b3eca67ce32ef3461758571a33e09202fa5f`; the built and isolated
strictly signed bundle kernels match at SHA256
`4fa70255585e2ff883e88025fa887859e137707a478bfa08e45b5ceb3a622b21`.
Full build/signature provenance is in
[native-build.json](evidence/context-menu/native-build.json).

- **Sides:** actual secondary-pointer invocation placed top/right/bottom/left
  and inline-end popups on the requested side, in bounds. Inline-end changed
  from right to left under RTL, with right-aligned content. The live official
  Sides examples were also opened on each physical side for comparison.
- **Forum reorder:** Beta's real rail menu selected Move up and visibly changed
  order to Beta, Alpha, Gamma; the menu dismissed.
- **Keyboard restoration:** Tab traversal focused Beta. The Context Menu key
  opened its actual Forum actions; Escape followed by the same key reopened
  that forum's menu. An AX activation click alone is not keyboard traversal.
- **Destructive confirmation:** Remove forum opened the accepted shared Alert
  Dialog, with Cancel initially focused. Cancel preserved Beta and the order.
  Reopening and confirming Remove produced Alpha, Gamma and dismissed both
  surfaces, exercising the real controller callback against fake storage.
- **Touch presentation adapter:** a local iOS theme-platform override exposed
  More Options; selecting it opened the real forum sheet. Move down changed
  order to Gamma, Alpha and closed the sheet. This is macOS pointer operation
  of the touch presentation, not a touch-device run.

The reviewer quit only its own fixture, closed its own reference tab and
released the shared desktop lease after inspection.

## Focused verification

All commands use randomized seed `826145` and `--no-pub`:

- `flutter test test/d_context_menu_test.dart test/d_dropdown_menu_test.dart
  test/d_popover_test.dart test/styleguide/context_menu_examples_test.dart
  test/instance_actions_accessibility_test.dart
  test/modal_controller_lifecycle_test.dart`: 64 passed on the original,
  accepted-parent and refreshed current-main candidates.
- `flutter test test/shell_navigation_integration_test.dart --name
  'ordering sites|removing a site'`: 21 passed, including actual long-press
  gestures, touch reorder arbitration, More Options, cancel/removal persistence
  and controller/session guards.
- After accepted Alert Dialog reconciliation, `flutter test
  test/instance_actions_accessibility_test.dart
  test/modal_controller_lifecycle_test.dart
  test/shell_navigation_integration_test.dart --name 'forum context actions|forum
  semantics action|instance actions|ordering sites|removing a site'`: 26 passed.
- Root and `profiles/full` `flutter analyze --no-pub` are clean. Fixture
  formatting, the debug macOS build and `git diff --check` passed.

These sets overlap; their counts are not a combined unique-test total.

## Accepted shared-owner correction

The final native RTL check exposed the inherited double-mirrored submenu
chevron: the indicator points right even though logical submenu navigation is
leftward. Menubar reviewer `01a08628-7042-7173-a37d-7f1f04eade66`
prepared the shared Dropdown Menu correction in commit
`430b46a0690a23613ca795b3a95a6f64da9b590e`, together with popup-local
focus scrolling. The Dropdown Menu reviewer consolidated this with the
registration-order correction on `codex/review-dropdown-menu-followup` at
`7110ef80`, then accepted it on local main at
`85f9265bf2593a7edc0693582b7eadf1c6645b8d` with tracking commit
`d647400602824226d70d1328fba2a141195dc559`. The accepted Dropdown
source is byte-identical to the prepared and natively inspected Git blob
`b5c53b46b86b28f8d8a9b6375b4798fdf7c233b6`.

Context-specific regressions reproduced both defects before the fix:
the RTL glyph is double-mirrored, and opening a constrained context popup in an
embedded Navigator moves its enclosing page by 62px. Both now pass. Context
Menu directly composes `DDropdownMenu`, so the correction requires no duplicate
engine or adapter change. The accepted parent also preserves live registration
order when item labels, enabled states or borrowed focus nodes change.

The parent owner records 50 focused passing tests and clean root/full analysis.
Menubar's source-exact native runtime
`e3104c9ae1547b90629f85d6e7a7bb97c863f6c7`, kernel SHA256
`71ca16cbe8d2b65a202de67dfe39f3863d58d817a828b7661c2004f8edd6f318`,
verified the combined source at 360px/200% text in LTR/RTL, reduced motion and
Plum RTL. Popup row navigation did not move the host; Arabic chevrons pointed
and opened left, and Right returned to the parent. This is shared-owner native
evidence, not a new Context Menu native run.

## Final acceptance

Candidate `c9979ec28e310617b9f31a189c098760e05fc074` starts from
accepted current main and brings in the Context Menu history. All other
component progress records and the accepted Dropdown/Popover sources are
preserved. The Context Menu, forum adapter, examples and fixture behavior are
unchanged from the completed native inspection; only the accepted shared fixes,
the implemented catalogue status and formatter-only layout differ. The
accepted Popover's new joined-control boundary prevents grouped-trigger
geometry from leaking into detached content and has no joined ancestor in
these inspected Context fixtures.

The final Context/Dropdown/Popover/styleguide/accessibility/lifecycle matrix
passes **67 tests**, including both fail-before regressions. The real-rail
ordering/removal matrix passes **21 tests** again, and the example status update
passes all **4 styleguide tests**, all with seed `826145`. Root and
`profiles/full` analysis are clean, touched Dart files are formatted and
`git diff --check` passes. Counts overlap and are not a unique total.

The final debug macOS integration build of
`tool/context_menu_review_main.dart` passed at source
`dd821a9d3b26c0591236e2234a903fe722c42ede`, with kernel SHA256
`1e81e58edc4aca5ac426b709c93a18f2df44f653298190729e6a2cf78918b6dd`.
This verifies compilation of the composed final source, not another native
launch.

All ten examples are marked implemented. Completed own-native evidence is
retained for unchanged Context behavior and exact-source parent evidence
covers the shared runtime corrections; no repeat full desktop pass is claimed.
The following input/platform limits remain explicit rather than being counted
as performed native interactions.

## Evidence limitations

Native Context Menu key entry and focus restoration passed. Shift+F10 did not
open through the available native key synthesizer; the exact key chord passes
the widget regression. The approved CUA surface has no long-press primitive,
and the rail's custom reader action was not exposed as a callable secondary AX
action. Actual long-press and custom-semantics callbacks are covered by focused
widget/integration tests, not claimed as native CUA gestures. No iOS/Linux
device run, spoken VoiceOver pass or pixel-diff equality is claimed.
