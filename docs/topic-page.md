# Desktop topic workspace

Opening a topic keeps a reduced, resizable topic list beside the reader when
the reader can remain at least 825 logical pixels wide. The list uses its
current width between 304 and 480 pixels, shrinking as needed to preserve the
reader minimum. Below 1129 pixels of available content width, the topic
replaces the list. This uses the space left after navigation and composer
sizing, rather than the full window width. Touch layouts retain their existing
split threshold.

## Navigation and retained state

- The existing collapse control returns to the full-width source list. It sits
  in the topic header when the list is hidden, or beside the visible list heading.
  The list stays mounted, preserving its filters and scroll position.
- The header has no separate navigation row, Switch topic dropdown, or topic
  position counter. Previous/next buttons remain in the visible list footer;
  keyboard sequences navigate the same source list at every width. Each topic
  keeps its reading position, and **U** returns to the list.
- Navigating while writing preserves the draft and its original destination.
  A return-to-topic action appears in the composer when reading another topic.
- Direct topic links use the header collapse control and keep the existing navigation
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

`DesktopTopicPage` supplies search when desktop window chrome cannot carry it;
`DesktopNavigation` composes the Native popover and existing sidebar.
The old desktop sheet host and sheet navigation scope are removed.

Widget coverage includes list/reader restoration, topic switching, draft
ownership, keyboard and picker focus, tabs, all three dock positions, narrow
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
