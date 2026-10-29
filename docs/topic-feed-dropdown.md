# Adaptive topic views

`TopicFeedMenu` presents up to three Native segmented toggles beside the list's
filters. The current view always stays visible. Actual Native control widths,
including their labels, counts and text scaling, determine how many fit. Hidden
views appear under the ellipsis; no ellipsis is needed when every view fits.

Latest, Unread, New, Unseen and Trending select the existing server feed routes.
Unified New opens All, Topics and Replies, while legacy New selects the server's
new-topics feed directly. Top opens Year, Quarter, Month, Week, Today and the
supported All Time choice. The current New subset or Top period appears in its
segment's label. Signed-out readers see Latest, Top and Trending.

Desktop overflow lists only hidden views. On iOS and Android it opens a Native
adaptive bottom sheet containing every view, including the current one. Menu
entries retain their counts and selected checkmark. Counts use the existing live
category and tag scope. The overflow badge counts the union of hidden New and
Unread: Unified New already includes the unread replies; legacy New topics and
Unread replies are disjoint.

`TopicFeedMenu` lives in `lib/src/shell/topic_feed_menu.dart` and remains exported
by `topic_list_navigation.dart`. A bounded parent supplies the room available to
the switch. Its optional `compact` flag replaces labels with icons while keeping
counts and accessible names. It also follows `DFitRow.tightOf` on touch platforms.
`maxVisibleViews` may reserve room for adjacent filters, from one to three views.
All control artwork, surfaces and touch targets belong to existing Native
components; the switch only composes and measures them.

`test/topic_view_switch_test.dart` checks fitting, current-view retention,
overflow contents and deduplication, actual selected modes, New subsets, every Top
period, legacy and signed-out behavior, large text, compact accessible names and
phone sheets. Set `TOPIC_FEED_CAPTURE_DIR` to export deterministic Flutter fixture
PNGs. `test/topic_feed_menu_test.dart` retains the adaptive-menu, keyboard, focus,
scrolling and dismissal checks. `test/topic_list_navigation_test.dart` verifies
server requests, scoped live counts, restored route state, layout and navigation.
