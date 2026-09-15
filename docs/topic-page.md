# Desktop topic workspace

Opening a topic keeps a reduced, resizable topic list beside the reader when
the content workspace is at least 880 logical pixels wide. The list uses its
current width between 304 and 480 pixels, leaving at least 520 for the reader.
In narrower workspaces, the topic replaces the list.

## Navigation and retained state

- **Topics / Messages** returns to the full-width source list. The list stays
  mounted, preserving its filters and scroll position; it is offstage only
  when the workspace cannot fit both panes.
- **Switch topic** opens the existing Native combobox. It starts with all
  loaded topics and searches those titles. **Load more topics** fetches the
  next source-list page when available.
- Previous/next buttons appear in the list footer while the list is visible,
  and in the reader navigation on narrower workspaces. The keyboard sequences navigate the same
  source list. Each topic keeps its reading position. The existing **U**
  shortcut returns to the list; Escape dismisses an open picker.
- Navigating while writing preserves the draft and its original destination.
  A return-to-topic action appears in the composer when reading another topic.
- Direct topic links receive a Back action and keep the existing navigation
  fallback when there is no source list.

## Window size

The rail remains visible. Below 1100 logical pixels, the sidebar is accessible
through a **Navigation** popover beside the rail. It closes after navigation
and when the permanent sidebar returns.

The composer lives inside the content workspace. Side docking requires a
480-pixel reader plus a 360-pixel editor and divider. When these cannot fit,
the editor moves to the bottom and restores the preferred side when space
returns. The draft, editor selection, and reader survive these transitions.
Touch layouts retain their existing split-view and bottom-composer behavior.

## Implementation and verification

`DesktopTopicPage` composes Native buttons and combobox controls;
`DesktopNavigation` composes the Native popover and existing sidebar.
The old desktop sheet host and sheet navigation scope are removed.

Widget coverage includes list/reader restoration, topic switching, draft
ownership, keyboard and popup focus, tabs, all three dock positions, narrow
windows, RTL, and touch behavior. The isolated
`tool/topic_page_review_main.dart` fixture supports native macOS inspection
with fake topics and separate preferences.

Restoring the desktop split view passed root static analysis and 150 focused
widget tests across the topic page, topic inbox, keyboard navigation, and
composer boundary suites. Coverage includes dragging the list divider in LTR
and RTL, retaining both pane states across narrow/wide transitions, highlighting
the selected topic, and showing one set of previous/next buttons.

The macOS fixture build passed. Native inspection verified the reduced list,
switching topics by clicking a list row, the narrow reader fallback, and the
list returning when widened. Mobile behavior has widget coverage only.
