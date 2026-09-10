# Nested menu pointer protection

Dropdown Menu, Context Menu and Menubar share the pointer-intent behavior in
`DDropdownMenuContent` / `DDropdownMenuSub`. Each open menu level owns its own
triangle and pending sibling hover. Nothing is painted and there is no toggle.

The triangle starts at the last pointer position over the active submenu's
trigger and ends at the rendered popup's near vertical edge, with an 8px
vertical tolerance at its corners. Reading global bounds on each movement
accounts for RTL, collision flips, vertical shifts and overlay transforms.
This follows the dynamic safe-area approach described in
[Floating UI's pointer-intent documentation](https://floating-ui.com/docs/usehover#safepolygon).

A sibling row cannot change highlight, close the active submenu or open its
own submenu while the mouse moves toward the popup inside that triangle.
Continued progress refreshes the grace period; a 300ms pause over a sibling
accepts its hover. Leaving the triangle or reversing direction accepts the
current row immediately, including when the pointer stays within that row.
Entering the popup or leaving the parent clears pending work. Clicks and
keyboard input override pointer intent; keyboard input in a deeper menu also
cancels pending intent in its ancestors. Timers are cleared on item removal,
submenu closure and disposal. Touch and pen do not use the triangle.

The Chat channel action menu was the remaining application use of Flutter's
`SubmenuButton`. It now uses the Native Dropdown Menu and its trigger, items and
separator, retaining channel settings, notification state, busy guards,
starring, leaving/closing, focus and tooltips. Its touch sheet remains the same.
Other application `MenuAnchor` uses contain flat menus, so they do not have this
nested-menu switching problem. Navigation Menu uses a shared top-level panel
instead of the nested command-menu owner.

## Verification

- The three basic diagonal regression cases fail against the pre-change shared
  menu source and pass with the fix.
- `test/menu_pointer_intent_test.dart` exercises every shared menu family:
  right and left opening, RTL, collision flips and shifts, upward and downward
  traversal, multiple nested levels, long continuous movement, deliberate
  pauses, reversal, vertical switching, clicks, keyboard override, Escape,
  outside dismissal and removal.
- Focused checks include the dropdown, context menu, menubar, popover and table
  tests and all three styleguide suites, including narrow RTL and large text.
- Chat's sidebar integration checks exercise the migrated desktop actions and
  the existing touch sheet with local fake data.

Native inspection and final integration results are recorded below after the
candidate is reconciled with current local main.
