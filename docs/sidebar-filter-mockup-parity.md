# Sidebar and filter parity

Reference: `discourse-native-mockups` snapshot `54ba01c`, including the sidebar
and filter behavior in `f265e6e`, `41d4082`, `c99e7c2`, and `31bdc07`, with the
later filter refinements applied. Search, composer, Start content, and the
outer desktop frame are implemented by their respective groups.

| Final behavior | Native implementation |
| --- | --- |
| Category and tag belong to Filters | The editor includes the current list category and tag in its counted pill. Apply replaces those scopes independently of other server clauses; Clear removes both. A list picker replaces its one tag. Existing server syntax for negative and multi-value clauses remains available. |
| Editable tokens and keyboard navigation | Editing a token stages its key. Backspace dismantles the value and key, arrows navigate suggestions, Enter selects and then applies, and Escape clears the staged input or dismisses the menu. Keys use Native icons; tokens use an accent key with a stronger value. |
| Category hierarchy | The filter picker shows one sibling level. A separate Native button drills into children, the first row names the enclosing category, and left/right keys move between levels. Search spans the tree and includes the parent path. Selecting a parent is independent of opening its children. |
| Real tag data | List pickers and token suggestions sort by usage, then stable label. Category lookups pass the actual category ID to the existing read endpoint, rather than borrowing composer write restrictions. Cached fallbacks retain account boundaries. |
| One sidebar selection | Topics is selected for the plain list. Category/tag scopes highlight their own row, with a selected tag retained even when absent from the cached top tags. Category navigation shows children or a leaf's siblings; the section heading moves up. Clicking a selected scope clears it. Start and Messages navigate the focused tab to the relevant list. |
| Community identity | The sidebar begins with the forum's mark and name. Its Native dropdown selects an existing forum. Forum, Chat, Shortcuts, Drafts, account access, plugin permissions, and custom sections remain available. Desktop composition stays in the title bar; mobile retains its sidebar action. |
| Distinct Chat pages | Chats, Channels, and Threads are sidebar destinations until a directory is open. Desktop navigation opens or focuses each directory's own tab; at the tab limit it navigates the active tab and preserves Back/Forward history. The sidebar follows the focused page. Mobile retains ordinary navigation. |
| Sticky, quiet Chat controls | The inbox controls pin above the shared conversation and voice-room viewport, with a Native gradient blur at the lower edge. The sidebar tab count is a quiet number with unread semantics. Page filters, category/tag controls, category bells, and presence use existing Native variants and sizes. |

The regression coverage exercises scope round-trips, replacement and clearing,
category browsing and search, keyboard selection and scrolling, focused panel
navigation, late lookup retirement, account changes, tag usage ordering, custom
sections and plugin availability, independent directory tabs and reuse, and
sticky controls. Related filter, taxonomy, sidebar, route, lookup API, Chat, and
notification ownership suites run by explicit file path; analysis targets the
changed Dart files.

Real-font widget renders cover desktop and phone filters at 200% text and the
pinned Chat sidebar in light and dark themes. The Native picker suites also
cover narrow layouts and RTL. These are rendered widget fixtures and API
request-shape checks; no physical-device or authenticated server run is claimed.
Optional exports use `SIDEBAR_FILTER_REVIEW_DIR` with
`sidebar_filter_parity_test.dart` and `chat_sidebar_parity_test.dart`.

The October 9 follow-up compares Chat navigation and scrolling against mockup
snapshot `c39ad50`. It covers full-tab navigation through all three directories,
Back/Forward, conversation and directory focus in both desktop panels, and
filters remaining pinned and interactive through long voice-room lists at
normal and doubled text size. Pointer-wheel scrolling over the controls uses
the same sidebar viewport. These checks use the existing Native controls.
