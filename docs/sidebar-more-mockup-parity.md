# Sidebar More

Reference: `discourse-native-mockups` snapshot `7c86328`, `NAV_MORE_ITEMS`
and `NavSidebarContent` in `src/App.tsx`.

The desktop Forum sidebar expands More in place. It uses the existing
Native sidebar button and collapsible components, with a trailing disclosure
chevron, 20px directional indentation, ordinary menu-row hover and selection,
and 20px of space before the category section. It has no dropdown, submenu
guide, or separator. Its labels, icons, hit bounds, and text scaling use the
sidebar's existing Native presets.

Categories, Groups, Badges, Bookmarks, Settings, and Preferences open their
existing Native pages. Bookmarks and Preferences require a connected account;
Badges follows the forum's capability, staff retain Admin, and configured
native links retain their forum labels. External community links remain in
Shortcuts.

Navigation keeps More expanded. More and its selected child are highlighted
together; the child stays in its original indented position. Direct navigation
to one of these pages reveals it. A user can collapse More while its child is
active, retaining More's highlight. Switching forums initializes expansion
from the destination in that forum. Tab enters the expanded destinations in
display order; Enter and Space activate the disclosure. Closing removes the
children from focus, hit testing, and accessibility. The mobile dock retains
its existing overflow surface.

`sidebar_more_parity_test.dart` covers the connected and anonymous lists,
inline geometry, visible hit bounds, expansion semantics, keyboard navigation,
active rows, direct routes, forum switching, and 200% text. Related destination
and badges tests cover focused panels and capability filtering. The broader
`shell_navigation_integration_test.dart` has 15 unrelated failures which also
reproduce on unchanged main; its More and Shortcuts cases pass.
