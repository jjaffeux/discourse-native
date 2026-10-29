# Adaptive topic views

Feed selection and counts are implemented. Full mockup parity is pending the
production row allocation described below and a Native selection treatment.

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

The production `TopicListFilterBar` currently gives its leading switch the
whole `DFitRow` width, rather than the width remaining beside its sibling
filters. The switch therefore fits against too much room. A rendered
`MainContent` comparison at 560px keeps three views and wraps Tags, while a
temporary two-view cap keeps the entire row together. At 520px, a temporary
one-view cap keeps it together. These comparison caps were reverted.
`DFitRow.tightOf` exposes only a compression boolean. `DControlExpanded` can
allocate remaining space only in a non-wrapping row, with no minimum-width
fallback; a production experiment overflowed at a narrower width. Item 3's row
layout needs to supply a bounded remaining width while preserving the minimum
current-view-plus-overflow control and its wrapping fallback.

The current `DToggleVariant.segmented` renders a full-height, small-radius
selected surface. The mockup instead calls for a round raised segment inside a
round track: 30px track / 26px segment with a 2px inset on desktop, 36px / 32px
on a phone. Existing `DToggleVisualStyle` can change the radius but has no
raised-fill or inset preset; `DToggleGroup.inset` uses a different frame and
selection treatment. Exact selection geometry and surface therefore depend on item 10's shared
Native presentation. The user has authorized necessary kit changes; item 3 owns
the remaining-width layout and item 10 owns the shared segmented preset. This
branch has not added a parallel presentation or an application-level surface
workaround.

The `production view row remains reachable across available widths` case in
`test/topic_list_navigation_test.dart` captures actual `MainContent`,
`TopicListNavigation` and `TopicListFilterBar`, rather than a separately bounded
switch. It checks control bounds and phone overflow access. With
`TOPIC_LIST_CAPTURE_DIR` set, it writes screenshots and a CSV of row/switch
constraints, shown views and filter positions. `TOPIC_LIST_REVIEW_NAME` sets the
output prefix. This evidence records the pending allocation; the test does not
assert that the incomplete fitting behavior matches the mockup.
