# Dropdown Menu

Reference: <https://ui.shadcn.com/docs/components/base/dropdown-menu>

Registry source: <https://ui.shadcn.com/r/styles/base-nova/dropdown-menu.json>

Captured 2026-09-09:

- Markdown SHA256: `3a8ab9398fa074c3cdf023e31bc9368a3b6bafb0b0f146a326eb2c76808ba7fa`
- Registry SHA256: `335c59dba30145f434a9cc9ccb0438a3c5e2afe857fc11b029de1ecb415224d7`

## Reference mapping

- `DropdownMenu` / `DropdownMenuTrigger` / `DropdownMenuContent` map to
  `DDropdownMenu`, `DDropdownMenuTrigger`, and `DDropdownMenuContent`, backed by
  the shared `DPopover` overlay lifecycle and positioning owner.
- Popup geometry follows base-nova defaults: 160px sample width, 128px minimum
  content width, 4px side offset, 4px internal padding, lg radius, popover
  surface, foreground/10 ring, shadow-md, and 100ms popover transition.
- Items map the registry's `px-1.5 py-1 text-sm gap-1.5 rounded-md` to 6px
  horizontal padding, 4px vertical padding, 14/20 interface type, 6px icon gap,
  16px icon/check/chevron slots, and a 28px desktop row. Touch platforms grow
  rows to 48px invisible/visual targets.
- Labels use 12/16 medium muted text and separators use a 1px border-colored
  rule with 4px vertical margin and negative horizontal menu padding.
- Destructive items use the destructive foreground and destructive hover/focus
  tint (`10%` light, `20%` dark).
- Checkbox and radio items keep state external through `checked`, `value`, and
  callbacks. They default to staying open for multi-choice editing.
- Submenus are nested dropdown menus positioned on `inlineEnd`, mirrored in RTL,
  with directional-key open and submenu-local Escape close before parent close.
- `DDropdownMenuShortcut` is presentation-only and right-aligns in the row's
  trailing slot with 12/16 text and wide tracking.

## Native adaptation

The Flutter port does not use Material `MenuAnchor` as the generic owner. It
uses the library Popover owner so live theme changes, reduced motion, collision,
lifecycle loss, outside dismissal, Escape behavior, and trigger-focus
restoration are consistent with the rest of the shadcn overlay components.

Rows use Flutter focus nodes and actions for keyboard activation, arrow
navigation, Home/End navigation, typeahead, and tab-out dismissal. The component
accepts caller-owned leading/trailing widgets so app icons can remain native to
the product while preserving shadcn geometry.
