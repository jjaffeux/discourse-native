# Control consistency — 2026-09-11

The [2026-09-13 compact sizing update](compact-control-sizing.md) supersedes
the four-size geometry below. Current controls use small 24px, regular 28px
and large 32px; extra-small has been removed.

The user approved a shared visual contract for buttons, selects and menu
triggers after comparing the topic feed filters and footer with the
[Base UI dropdown reference](https://ui.shadcn.com/docs/components/base/dropdown-menu).
This follow-up supersedes the historical Button compatibility-style policy.

## Ownership

`foundation/control_style.dart` owns compact heights, radius calculation,
normal icon size/gap, transition duration, outlined fills, and the single
border/joined-edge/exterior-ring painter. Button and Select use that foundation.
`DButtonDecoration` remains a public type alias so existing callers can inspect
the surface without importing internals. Select keeps its focus, typeahead,
form, read-only, selection, semantics and popover owners.

The application uses only `primary`, `outline`, `secondary`, `ghost`,
`destructive` and `link`. Old enum names remain source-compatible for external
plugins, but resolve through those same reference styles. They no longer read
a separate legacy palette or use different pressed-fill behavior.
`DiscourseButtonTheme` remains compatible theme data; its disabled-opacity
setting still works. It no longer controls button colors.

Migration choices:

- Standard actions become outline; flat/transparent actions become ghost.
- Dangerous actions become destructive; affirmative success actions become
  primary. Labels and icons continue to express meaning independently of color.
- Selected/accented controls use primary. Calendar navigation and secondary
  actions use outline, dismiss actions use ghost, and web actions use link.
- All button-like controls use `DControlSize.extraSmall`, `small`, `regular`,
  and `large`: 24, 28, 32, and 36 logical pixels. Component size typedefs alias
  this same enum. The Button styleguide is the sizing authority.
- `insetSurface`, button padding overrides, Toggle constraint/padding overrides,
  Sidebar custom heights, and application height wrappers have been removed.
  Icon and labeled buttons share the same scale. Text scaling expands their
  surfaces consistently; invisible touch targets remain at least 48px.
- Taxonomy filter buttons now use outline. Topic footer actions use kit variants
  without local background/border/hover mixtures. The incoming-topics action and
  chat add-menu button also drop their local paint overrides.
- The category-tinted split controls retain their semantic category colors.
  Existing compact navigation/container geometry exceptions are listed in the
  adoption test, rather than permitting arbitrary new local overrides.

`DDropdownMenuTrigger.button` composes an outline DButton by default and wires
activation, borrowed focus, expanded semantics and disabled state. The existing
builder remains for richer compositions such as avatars and split controls.
A menu does not introduce a second button or a second interaction owner.
Labeled notification menus default to outline; their icon-only form uses ghost
or primary according to emphasis.

Button and Select are a coordinated family, not identical widgets. Following
the reference, Select retains regular-weight value text, a muted chevron and
input-border semantics; its light surface is transparent, while an outline
button uses the background token. Dark outline fills share the same input
alpha calculation. Site colors, fonts and configured radius remain authoritative.

## Drift checks and review surface

The Button styleguide replaces the old Application variants showcase with
**Control consistency**: all four sizes of action buttons, selects, dropdown triggers,
disabled states, and a joined reply/bookmark/notification group. All controls
are interactive and retain local state across palette changes.

- `control_style_adoption_test.dart` rejects legacy variants in application and
  kit compositions, and inventories direct application DButton color, radius
  and padding exceptions. Its scanner excludes comments, strings and nested
  widget arguments. This is a source boundary guard, not a complete Dart lint.
- `control_consistency_test.dart` verifies shared dark surfaces, including the
  production TopicTaxonomyButton, menu focus restoration, disabled activation,
  feed/category selection and notification selection.
- `control_consistency_golden_test.dart` stores twelve reviewed snapshots:
  rest, hover and open-menu states in Light, Dark, Forest and Plum. It uses
  repository JetBrains Mono fonts at 720×480 with a macOS platform override
  and mouse input for portable regression comparisons;
  this is not a claim of reference-font pixel equality. The native review uses
  the actual application font.
- `tool/control_consistency_review_main.dart` mounts the same specimen and the
  production taxonomy trigger adapter without accounts or network operations.

## Verification

Flutter 3.47.2; locked dependency resolution, no lockfile or SDK changes.

- 135 focused Button, Button reference, Select, Dropdown Menu, Button Group,
  Button examples, taxonomy and notification-menu tests passed.
- 145 consumer/contract/golden checks passed, covering chat drawer/header,
  incoming topics, Input, message inbox menu, filter and notification ownership,
  topic creation, bookmark sessions and production Select consumer fixtures.
- 41 calendar, event-card, event-directory and chat-drawer checks passed after
  choosing outline/ghost/link for secondary calendar actions.
- Static analysis passed with no issues. Final foundation/contract/golden run:
  146 passing checks; the final alias-ring, notification-default and macOS
  golden follow-up passed all 55 affected checks.
- Native macOS debug build, isolated signature/entitlement verification and
  actual launch passed. Reviewed default/small/disabled controls in dark and
  light, then Plum at 320px, 200% text and RTL. Exercised dropdown keyboard
  selection and focus, Select keyboard selection, and notification pointer
  selection. The production taxonomy triggers were mounted alongside the
  specimen. The isolated app was quit and the desktop lease released.
- Opened the official Base UI dropdown in Chrome and inspected its outline
  trigger, open menu, spacing and focus composition. App colors/radius are
  deliberately theme-mapped; no exact screenshot equality is claimed.
- The two broader topic-reading/lifecycle files expose nine existing failures.
  Running their untouched tests against an archived copy of starting commit
  `75244dc2` reproduces the same nine: read-position expectation, two off-page
  category composer assertions, sidebar New Topic placement, progress Slider
  lookup, progress legacy-variant assertion, Scrollbar lookup, administrative
  action lookup, and bookmark variant assertion. No additional failures appeared
  in these two files. A stale raw-Material adoption exception for the already
  migrated topic-list period select was removed.

No iOS/Linux device session, authenticated live-app review, or spoken screen
reader session was performed. The existing focused tests cover those platform
layout/semantics paths without claiming device verification.


## Unified sizing follow-up

Select, Toggle, Toggle Group, Input Group buttons, Combobox inputs and button
triggers, date-picker triggers and form fields, pagination, carousel actions,
navigation-menu triggers, tabs, menubar triggers, and sidebar
menu buttons use the shared size API. Dropdown and notification menu triggers
forward their size to Button. Layout widths and popup/content sizing remain
independent of trigger height. Multi-line labels and accessibility text scaling
can grow controls; applications must not force a different height with wrappers.

The cross-component `control_size_scale_test.dart` checks rendered heights and
activation for every size. The Button Control consistency example presents
Button, icon Button, Toggle, Select, and Dropdown together.


Verification on 2026-09-11: macOS debug build; native wide/dark and 390px/light
production toolbar, category popup, 200% RTL, and the Button Control consistency
example with extra-small Select activation. Flutter goldens use the bundled
ControlGolden font at 720×480 on the Flutter test renderer and cover light,
dark, forest, and plum in rest, hover, and open-menu states. These are distinct
from the native macOS inspection. No iOS or Android device run was performed.

Final verification: static analysis reported no issues; 526 focused widget,
interaction, shell integration, and golden checks passed after integrating
the latest local main.
