# Sidebar More

Reference: `discourse-native-mockups` commit `13db54c`, `NAV_MORE_ITEMS` and
the Places list of `NavSidebarContent` in `src/App.tsx`.

More opens in the sidebar on desktop and phone. Opened, it gives its place to
the rows it held, flush with the rows above and at their height, and a quiet
Less row folds them back. Less is the section's foot: smaller muted words and
an up chevron, 12 and 11 points on desktop, 14 and 13 in the phone drawer. There
is no dropdown, submenu guide, separator, indentation, or disclosure chevron on
More itself. A space of 20 points before the category section remains on
desktop.

Categories, Groups, Badges, Bookmarks, Settings, and Preferences open their
existing Native pages. Bookmarks and Preferences require a connected account;
Badges follows the forum's capability, staff retain Admin, and configured
native links retain their forum labels. External community links remain in
Shortcuts.

Navigation keeps the rows open. More never lights up; only the row you are on
does, and once folded that row stands above More. Direct navigation to one of
these pages reveals them. Switching forums initializes the open state from the
destination in that forum.

More and Less leave the tree when activated, so a keyboard user's focus follows:
More hands it to the first revealed row and Tab continues through the rest to
Less, and Less hands it back to More, scrolling it into view when folding left
it above the list. A press does not move focus, because a ring on the next row
would be a mark the pointer never asked for.

`sidebar_more_parity_test.dart` covers the connected and anonymous lists, flush
geometry, both directions, the phone drawer sizes, visible hit bounds,
expansion semantics, keyboard focus, active rows, direct routes, forum
switching, and 200% text. Related destination and badges tests cover focused
panels and capability filtering.
