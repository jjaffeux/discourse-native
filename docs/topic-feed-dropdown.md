# Adaptive topic views

Feed selection, scoped counts, remaining-width allocation and the shared Native
selection treatment are integrated. Production checks cover desktop widths down
to 340px and phone overflow, including keyboard focus and count deduplication.

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

`TopicListFilterBar` marks its switch with `DFitRowItem(leading: true)`.
`DFitRow` measures the category, tag, and filter controls before assigning the
switch its remaining width through `DFitRow.availableWidthOf(context)`.
`TopicFeedMenu` chooses views against that measured width and reports its actual
minimum size. The row wraps when the current view and overflow cannot fit.

When full labels would take a third row, `DFitRow` shortens them again. If needed,
the category path marked with `DFitRowItem(last: true)` moves to the final row.
Ancestors keep their marks, and the last selected category keeps its name.
The unchosen deeper level shows a plus, or a prohibited glyph for exact scope.
Every shortened control retains its accessible name and open menu state.

Phone filters use the existing Native `filter` preset at 36 points with
14-point labels and icons. Desktop retains 30-point filters and 12.5-point labels.
The bar listens to `DPageHeaderScope` and requests `DFitRow.compact` when the
owning phone heading is fully retracted. Category and tag controls then show
meaningful icons while active styling and filter counts remain visible.
Native reference text scaling preserves accessibility and app zoom.

`DButtonGroup.inset` supplies the same raised round presentation used by topic
recommendations. Child toggles and the ellipsis action use the existing
`segment` size, with `DToggleVariant.segmented` for selectable views. Native owns
a 30px track with 26px segments on desktop and a 36px track with 32px segments
on phones. The kit also owns the 2px inset, shared gaps, raised fill, focus
treatment, and touch targets. New and Top retain
their independently focusable dropdown triggers. Fitting measures the actual
Native frame and children, including the frame's insets and spacing, without
copying those metrics into application styles.

The `production view row remains reachable across available widths` case in
`test/topic_list_navigation_test.dart` captures actual `MainContent`,
`TopicListNavigation` and `TopicListFilterBar`, rather than a separately bounded
switch. It checks control bounds and phone overflow access. With
`TOPIC_LIST_CAPTURE_DIR` set, it writes screenshots and a CSV of row/switch
constraints, shown views and filter positions. `TOPIC_LIST_REVIEW_NAME` sets the
output prefix. The test uses bundled fonts and asserts that the switch and
filters share one row at 560px and 520px. Smaller widths retain reachable controls
through the wrapping policy.

`test/topic_list_responsive_filters_test.dart` checks phone header compaction,
selected scope and count retention, 320-point deep paths at larger text sizes,
and category menu state while path levels disappear. Set
`RESPONSIVE_FILTER_REVIEW_DIR` to export its Flutter fixtures.
`test/sidebar_filter_parity_test.dart` checks that the Filters list reaches the
sheet edge and that its last choice remains reachable above the keyboard and
bottom safe area on iOS and Android.
