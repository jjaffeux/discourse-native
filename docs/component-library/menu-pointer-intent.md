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

## Integration and native inspection — 2026-09-10

Implementation `6e251059` was integrated into a candidate based on local main
`e440185d`, preserving the concurrent conditional-overflow viewport changes.
The Chat root uses a 280px width and a 220px notification submenu. The fixed
root width avoids asking the new overflow LayoutBuilder for intrinsic width.

The final candidate `193ff068` also preserves main's accepted menu hover-color
change. It passed 140 focused menu/styleguide tests and 53 Chat
sidebar integration tests. `flutter analyze --no-pub` reported no issues;
`flutter build macos --debug --no-pub -t lib/styleguide_main.dart` succeeded.

The native styleguide from `2f06606c` was launched as an isolated macOS review
bundle with a separate identifier and permitted debug entitlements. Its shared
pointer-intent implementation is unchanged by the subsequent integration.
Inspected Dropdown Menu in the current app's dark palette: nested opening,
deepest Escape, right-arrow reopening, and Message selection. Inspected Menubar
in the light palette: File → Share → Notes. Inspected Context Menu in the light
palette at a 360px preview width: secondary-click opening, More Tools submenu,
and Name Window selection. Menus retained their existing appearance and all
three selection paths closed their popups.

Native CUA exposes clicks and keyboard input but no standalone pointer-move
operation, so continuous diagonal hover paths were verified with Flutter mouse
gesture tests, not claimed as manual native hover verification. Chat migration
was exercised with production widgets and fake data in widget tests; it was not
inspected against a live account. No iOS or Linux device run was performed.

Merged into local main as `793de4d3` from the repository's main checkout.

## Hover gaps — 2026-09-10

Crossing a separator after closing a hovered submenu used to reveal keyboard
focus restored to its trigger, briefly highlighting `Invite users` on the way
from `New Team` to `GitHub`. Each menu now remembers pointer highlighting even
over separators, labels, disabled rows, padding and outside the popup. Keyboard
input restores focus highlighting and clears the hovered row across ancestor
menus. Escape also restores the owning row's highlight through the popover's
close callback, which handles that key before the row receives it. Pointer
hover still leaves actual focus and scroll position unchanged.

The light/dark Composition regressions and the pointer-to-keyboard regression
failed against the original source. With the fix, 148 focused dropdown,
pointer-intent, context-menu, menubar, popover, data-table and styleguide tests
pass, as do 50 Chat sidebar integration tests. `flutter analyze --no-pub` is
clean and `flutter build macos --debug --no-pub -t lib/styleguide_main.dart`
succeeds.

Native inspection used an isolated macOS styleguide built from `d5a4d703`.
In the dark app palette at Fit width and the light palette at 360px, verified
submenu opening, Escape restoring the `Invite users` highlight, directional
navigation to `GitHub`, and selection closing the menu. The narrow preview
also exercised a submenu flipped to the left by collision handling. Continuous
hover paths were verified with Flutter mouse-event tests; the native CUA API
does not expose standalone pointer movement. No iOS or Linux device run was
performed, and Chat checks used production widgets with fake data.
