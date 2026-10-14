# Topic feed dropdown

`TopicFeedMenu` uses the same anchored Native dropdown on desktop, iOS, and
Android. It opens from the current feed button without a visible heading or
close button. The semantic menu label remains available to screen readers.

The menu retains feed counts, the selected checkmark, the grouped New subsets
for unified New, and direct Top period choices. Signed-out users see Latest,
Top periods, and Trending. The Native dropdown owns viewport constraints,
overflow scrolling, outside-press and Escape dismissal, and focus restoration.

`test/topic_feed_menu_test.dart` checks the anchored presentation, groups,
counts, selection, scrolling, and dismissal across desktop and mobile,
Standard and Liquid Glass, light and dark themes, and 200% text. Set
`TOPIC_FEED_CAPTURE_DIR` to export PNGs from the presentation test.
