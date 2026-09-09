# Context Menu source evidence

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

The Context Menu does not implement a second menu engine. The exact reviewed
Dropdown Menu candidate source is integrated only for isolated compilation and
tests while that owner completes acceptance. The Context Menu reviewer must
replace/reconcile it with the accepted main revision before any final merge.

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

## Prepared dependency pin

- Parent: Dropdown Menu
- Reviewer: `01a085cf-f401-7813-80da-7c687de8a5d5`
- Reviewed/current-main candidate branch: `codex/review-dropdown-menu-candidate`
- Exact source pin: `d273c27e788bb3991c773c7432e0b8c927715651`
- Evidence supplied by the parent reviewer: 47 focused Dropdown/Popover/Table/
  styleguide tests pass with seed `826145`; root and `profiles/full` analysis
  are clean. Native/browser acceptance and final main merge remain pending.

The parent API has no public virtual-pointer anchor. Context Menu therefore
keeps the 1px point-anchor adaptation locally while reusing all common menu
content/navigation/selection. No shared parent API was changed. Final review is
gated on the Dropdown Menu accepted merge SHA and must reconcile any correction
from its native review.

## Review boundary

Source preparation, exact-source mapping, full documented examples, forum-rail
adoption and focused widget regressions are prepared. Official rendered browser
comparison and isolated native macOS inspection remain with the independent
reviewer under the shared desktop lease. Required native proof includes pointer
placement, touch long press, keyboard/reader entry, focus restoration, nested
direction/Escape, outside dismissal, collision, live themes, 200% text, RTL and
the real forum-rail surface. No iOS or Linux device run, spoken VoiceOver pass
or pixel-diff equality is claimed by this implementation task.
