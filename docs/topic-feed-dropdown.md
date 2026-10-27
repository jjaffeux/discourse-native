> Historical design and capture notes. The app now uses the [solid appearance](material-mockup-parity.md), with [depth from the current mockup](surface-depth-mockup-parity.md); earlier glass and depth measurements describe the retired rendering.

# Topic feed dropdown

`TopicFeedMenu` opens a Native adaptive bottom sheet on iOS and Android and an
anchored Native dropdown on desktop. Both open from the current feed button
without a visible heading or close button. The semantic menu label remains
available to screen readers.

The menu retains feed counts, the selected checkmark, the grouped New subsets
for unified New, and direct Top period choices. Signed-out users see Latest,
Top periods, and Trending. The Native dropdown owns viewport constraints,
overflow scrolling, outside-press and Escape dismissal, and focus restoration.
The mobile sheet also supports pulling up to expand and swiping down to dismiss.

`test/topic_feed_menu_test.dart` checks the adaptive presentation, groups,
counts, selection, scrolling, and dismissal across desktop and mobile,
Standard and Liquid Glass, light and dark themes, and 200% text. Set
`TOPIC_FEED_CAPTURE_DIR` to export PNGs from the presentation test.
