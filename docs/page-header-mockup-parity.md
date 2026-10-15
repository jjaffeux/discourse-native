# Page header parity

Reference: `discourse-native-mockups` commit `3700183`, `PageHead` in `src/App.tsx` and `.head-mask` in `src/app.css`.

The shared API is `DPageSurface.headed`.
The title uses 22 px type, a weight of 700, and a line height of 1.25.
Its top space is 12 px on touch platforms and 20 px on desktop platforms.
The controls use 16 px of top space and 14 px of bottom space.
The page heading has no divider or second background fill.
The soft edge is a 14 px Native content fade, active more than 2 px from the top.
Pages with less than 120 px of scroll overflow keep their title.

| Routes | Heading policy |
| --- | --- |
| Latest, New, Unread, Top, Trending, category feeds, tag feeds | Title retracts. Feed selectors, filters, and actions remain. |
| Messages, personal folders, group inboxes | Title retracts. Folder and inbox selectors remain. |
| Bookmarks, Activity | Title retracts. Filters remain. |
| Groups, Badges, Categories | Title retracts. Directory controls remain. |
| Chats, Channels, Threads | Title retracts. Navigation and filters remain. The kit supplies the keyboard fallback. |
| Open chat channels and direct messages | One compact line from the first loading frame. The complete header and mobile tab bar retract together, including on short transcripts. |
| Preferences, Settings, About, AI Conversations | Title retracts. Selectors and actions remain. |
| Summary | Profile title retracts. Summary tabs remain. |
| Users, Tags | Title stays compact away from the top, including during programmatic jumps. |
| Assigned group topics | Title retracts. Query and person selectors remain. |

Topic readers, chat thread readers, group profiles, and embedded More topics panels retain their specialized headings.
Channel readers never use an expanded header or switch between full and compact layouts.
They use the shared scroll controller with `minimumScrollExtent: 0`; thread readers retain their existing scroll policy.
Inactive navigation previews do not set the active page's scroll threshold or move with its header.
The Start page has no page title in the reference.
Menus, dialogs, and composer headings are separate surfaces.

The styleguide and [component conventions](component-library/conventions.md) use the same API.
The old chat-specific header layout is removed.

## Validation

Focused checks cover each changed route and the shared Native layout.
Rendered widget checks cover 390×844 and 1100×800 viewports, light and dark themes, and 100% and 200% text sizes.
The checks include title reveal, control focus, touch swipes, pointer input, stable scroll positions, short viewports, keyboard return, and RTL layout.
The Groups route also has rendered checks with its production widgets.

Ten existing assertions also fail on unchanged `main` at `7bf6bfd91`:

| Test file | Existing failures |
| --- | --- |
| `test/topic_list_navigation_test.dart` | Eight picker-flow and fixture assertions. |
| `test/scroll_retracting_header_test.dart` | One assertion expects a resized full header to retain its previous spacer. |
| `test/topic_inbox_test.dart` | One filter-flow assertion. |
