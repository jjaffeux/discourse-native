# Control consistency — 2026-09-11

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
- Existing inset icon hit areas remain explicit through `insetSurface`; invisible
  touch targets remain at least 48px. Visual size and hit-target size are separate.
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
**Control consistency**: normal/small action buttons, selects, dropdown triggers,
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
