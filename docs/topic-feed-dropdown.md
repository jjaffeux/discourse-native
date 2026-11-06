# Adaptive topic views

Feed selection, scoped counts, remaining-width allocation and the shared Native
selection treatment are integrated. Production checks cover desktop widths down
to 340px and the phone's view pill, including keyboard focus and count
deduplication. The phone pill follows `discourse-native-mockups` branch
`test-mobile-layout` at `9b59748` (`ViewSwitch`, from `cd5cd18`).

On a desktop, `TopicFeedMenu` presents up to three Native segmented toggles
beside the list's filters. The current view always stays visible. Actual Native
control widths, including their labels, counts and text scaling, determine how
many fit. Hidden views appear under the ellipsis; no ellipsis is needed when
every view fits.

On iOS and Android it is one quiet `DButton` at the `filter` size, like the
Tags and Filters pills beside it, rather than a switch. It names the current
view and shows, on the name's baseline 7 points on, the view's own count, or
else what waits in the other views when that is above zero. Pressed anywhere,
it opens every view. Its accessible name is `View: <name>`, with
`, <n> topics` while the view's own count shows, as the desktop toggles say
it, or `, <n> more in other views` while that total shows. It keeps its name and its
12-point insets when the phone header retracts.

Latest, Unread, New, Unseen and Trending select the existing server feed routes.
Unified New opens All, Topics and Replies, while legacy New selects the server's
new-topics feed directly. Top opens Year, Quarter, Month, Week, Today and the
supported All Time choice. The current New subset or Top period appears in its
segment's label. Signed-out readers see Latest, Top and Trending.

Desktop overflow lists only hidden views. The phone pill opens a Native menu
bottom sheet containing every view, including the current one. The sheet
opens at its content height without a pull-to-expand step. Larger text and short
screens scroll within the available height. Menu entries retain their counts
and selected checkmark. Counts use the existing live
category and tag scope. The overflow badge counts the union of hidden New and
Unread: Unified New already includes the unread replies; legacy New topics and
Unread replies are disjoint. The phone pill's waiting total is the same union
over the views other than the current one.

`TopicFeedMenu` lives in `lib/src/shell/topic_feed_menu.dart` and remains exported
by `topic_list_navigation.dart`. A bounded parent supplies the room available to
the desktop switch. `maxVisibleViews` may reserve room for adjacent filters,
from one to three views. Neither width pressure nor a retracted header turns
views into icons: the desktop has no retraction, and the phone pill keeps its
name.
All control artwork, surfaces and touch targets belong to existing Native
components; the switch only composes and measures them.

`test/topic_view_switch_test.dart` checks fitting, current-view retention,
overflow contents and deduplication, actual selected modes, New subsets, every Top
period, legacy and signed-out behavior, large text, the phone pill's insets,
baseline, count rules and accessible names, and the phone sheet of every view. Set `TOPIC_FEED_CAPTURE_DIR` to export deterministic Flutter fixture
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
14-point labels and icons, as the mockup draws them; the kit's touch target
keeps each one pressable across 44 points. Desktop retains 30-point filters and 12.5-point labels.
The bar listens to `DPageHeaderScope` and requests `DFitRow.compact` when the
owning phone heading is fully retracted. Category and tag controls then show
meaningful icons while active styling and filter counts remain visible. It sets
`DFitRow.closeUp` only while the category path has separators, so the row
stands closer (6-point gap, 10-point quiet pill insets) only when that keeps
the path on its line. On a phone the unchosen Categories pill is its mark
alone at any header state.
Native reference text scaling preserves accessibility and app zoom.

`DButtonGroup.inset` supplies the same raised round presentation used by topic
recommendations. Child toggles and the ellipsis action use the existing
`segment` size, with `DToggleVariant.segmented` for selectable views. Native owns
a 30px track with 26px segments on desktop and a 36px track with 32px segments
on phones, where a choice of two takes columns as wide as its names rather than
equal ones. The kit also owns the 2px inset, shared gaps, raised fill, focus
treatment, and touch targets. New and Top retain
their independently focusable dropdown triggers. Fitting measures the actual
Native frame and children, including the frame's insets and spacing, without
copying those metrics into application styles.

The `production view row remains reachable across available widths` case in
`test/topic_list_navigation_test.dart` captures actual `MainContent`,
`TopicListNavigation` and `TopicListFilterBar`, rather than a separately bounded
switch. It checks control bounds and the phone pill's sheet. With
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
