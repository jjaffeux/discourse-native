# Desktop topic workspace — design A

Opening a topic replaces its topic list in the main workspace. With a side
composer open, the four columns are the rail, sidebar, topic, and composer.
The topic is a page, with no sheet backdrop or extra list column.

## Navigation and retained state

- **Topics / Messages** returns to the source list. The list stays mounted
  offstage, preserving its filters and exact scroll position.
- **Switch topic** opens the existing Native combobox. It starts with all
  loaded topics and searches those titles. **Load more topics** fetches the
  next source-list page when available.
- Previous/next buttons and the existing keyboard sequences navigate the same
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

Root static analysis and the macOS fixture build pass. The focused topic,
keyboard, composer, draft, boundary, and tab suites pass. Native macOS review
verified the four-column workspace, source-list search, draft destination and
return action, bottom docking on narrow windows, and the sidebar popover's
placement beside the visible rail. Mobile behavior is covered by widget tests;
no new physical-device verification was performed for this change.
