# Topic foot and dock toasts parity

Reference: `discourse-native-mockups` at `540cbac` (branch
`test-mobile-layout`), from its message: "the topic's foot tools in pills by
the dock, its count as the timeline says it; toasts said by the dock as it
lifts, what floats over it lifting too". The rules are `.topic-foot-tools`,
`.topic-timeline-float`, `[data-dock-lifted]` and `.dock-says` in `app.css`;
`PostCount`, `TimelineMenu`, `TopicActionsButton`, `LevelButton`,
`toastStore`, `toast`, `floatToast`, `liftDock` and `ToEnd` in `App.tsx`.
Line numbers below are of `git show 540cbac` for each file.

The first pass kept to what the kit allowed and marked the rest Needs
decision. The user then approved extending the kit for this round, and a
second pass built those rows; "Kit changes" below lists what the kit gained
and why.

## The topic's foot tools and count

| Mockup change | Native | Verified | State |
| --- | --- | --- | --- |
| The count says the post you are at in 17px bold strong and " / total" in 13px muted, tabular figures (`PostCount`, App.tsx diff 1633 to 1660). | `TopicPostCount` in `topic_progress.dart`: `DiscourseTypography.lg` w700 in `foreground`, `control` w400 at half `foreground` over `background`, tabular figures. | `topic_foot_tools_mockup_parity_test.dart` reads the spans' sizes, weights and features. | Done |
| The same count on the foot button and in the timeline (App.tsx diff 1480 to 1488, 1661 to 1692). | `TopicProgressButton` draws `TopicPostCount` as its label on every width, as the mockup's `timelineButton` does; the timeline panel's own count is the same widget. | The second test finds `TopicPostCount` as `topic-progress-selection` in the open timeline. | Done |
| The menu of more is a 40 circle with an upright ellipsis (App.tsx diff 1104 to 1120; app.css `.topic-foot-tools__tools > :last-child > button`). | `TopicActionsButton` shows `DIcons.ellipsisVertical`; the floating tool preset already draws it 40 by 40 with pill corners. | Icon and 40 by 40 surface asserted. | Done |
| The notification level button loses its chevron (App.tsx diff 1693 to 1700). | `showChevron` dropped from the topic's level button and the list's category and tag level buttons, which are the same mockup `LevelButton`. It is now 40 by 40, flush against the bookmark. | No `filterChevron` icon, 40 by 40, left edge on the bookmark's right. | Done |
| What acts on the topic at once in one pill on the well fill, 40 tall, parts set off by a rule (app.css `.topic-foot-tools__tools > *`). | Already so: `DButtonGroup.tool` on `DTokens.wellFill`, its split painter between parts. | Bookmark and level asserted inside one `DButtonGroup`. | Done (unchanged) |
| Icons 15 tall (app.css `.topic-foot-tools__tools svg`). | Already so: `DControlSize.floating` draws icons at 15. | Every foot icon measured 15 tall. | Done (unchanged) |
| A further tool joins the pill with the same rule (the assign shortcut, App.tsx diff 1588 to 1603, owned by the assignment slice). | A plugin returns, from `TopicPropertiesPlugin.topicProperties`, a `TopicPropertySection` with a `compactAction` and no `actions`. `_TopicHeaderTaxonomy` in `topic_inbox_header.dart` places every such section after bookmark and level inside the same `DButtonGroup.tool`, so the split painter rules it off. A section with `actions` goes to the actions sheet on a phone instead. | `test/plugins/boards/boards_topic_header_test.dart` pins Boards' part in the pill at 390 and 1000 wide. | Done (path exists) |
| The end parts of the pill padded 15 so they look centred in its curve (app.css `> * > button:first-child`, `> :last-child`). In the mockup the parts are content sized: `padding-inline: 12`, `min-width: 40`, the glyph at its own width from the leading inset. | A `DButtonVariant.tool` part at `DButtonSize.floating` inside a joined quiet group is content sized from 40 with 12 insets, 15 at the first part's start and the last part's end, its glyph from the leading inset (`d_button.dart`, `pillPart`). The topic foot is the only joined floating tool group; the header's filter-size group keeps its squares. A wider glyph, such as the assignment shortcut's user-plus, widens its part as the mockup's does. | `d_button_group_test.dart` "a floating tool pill sets its ends further in" (both directions, and the filter-size square); the foot test measures the bookmark's glyph 15 in and the level's part as `max(40, 12 + glyph + 15)`. | Done |
| Where you are is a pill as tall as the dock's circle (`--dock-round`) with 18 inline padding and 15px text, and the foot row as tall as that circle so the 40-tall tools centre on it (app.css `.topic-foot-tools`, `.topic-foot-tools .topic-timeline`). | `DButtonDensity.dockRound` draws `DMobileDockGeometry.circleOf` tall with 18 insets; `TopicProgressButton` uses it on a phone. `floatingHeightOf` is that circle on touch, and `TopicCornerControls` keeps its controls at least that tall and centred, so the tools sit on the pill's middle and a foot with no count settles in the corner the same way. | `d_button_test.dart` "a dock round pill is as tall as the dock circle beside it"; the foot test compares the pill with the shell's dock geometry, its 18 insets, and the tools' centres. | Done |

Capture: `flutter test --dart-define=TOPIC_FOOT_CAPTURE_DIR=<dir>
test/topic_foot_tools_mockup_parity_test.dart` writes the phone screen per
platform. `topic-foot-and-dock-toasts-mockup-parity/topic-foot-iOS.png` and
`topic-foot-android.png` are the current ones.

## Toasts said by the dock

| Mockup change | Native | Verified | State |
| --- | --- | --- | --- |
| On a phone a toast is said by the bar: lifted as for its peek, the toast's icon in the accent and its text at 13px medium strong where the hint goes, on one line with an ellipsis, for 2400ms, then the bar settles (App.tsx diff 176 to 208, 1489 to 1587, 1604 to 1632; app.css `.dock-says`). | `DMobileDockPeek.say` raises the bar through the peek's own lift (`_raise`, no second lift) for `sayFor`, 2400ms, and `DSwipeHint.saying` stands in the hint's place: a 12-tall glyph in `primary`, an 8 gap, 13px w500 `foreground`, one line with an ellipsis, 16 in from either side. A saying during the hint replaces its words without fading in again. A screen reader hears it through a live region; the mockup hides the hint from readers. | `d_mobile_dock_saying_test.dart`: lift, timing, style, live region, a saying during the hint, a newer saying cutting a settle short. | Done |
| A bar folded into its circle is brought back first; under a sheet or the grown bar the toast waits, tried every 150ms up to 30 times, then dropped (`toastStore.dock` effect). | Folded (`collapsed` or `destinationsHidden`), the bar asks `DScrollChrome.reveal()` and the peek tries again. Out, covered by a composer's sheet, its footer put away, under another route (`DRouteScope`), or with a place being moved, it waits. The session's peek holds the waiting saying and its timer, every 150ms for 30 tries; a newer saying takes its place. | Saying tests: covered then uncovered, dropped after 30 tries, grown then closed, folded under a `DScrollChrome` and revealed, and the bar or the peek going while a saying waits. | Done |
| Only a layout with no bar floats the toast over the page (`floatToast`). | `DToastController.teller` is tried before a card. The phone shell sets it to its peek's `sayToast` and clears it as it goes, so a wide layout, or a phone bar with no panel to grow into (the mockup's bar with no hint), keeps cards. | Saying tests for the controller in pure Dart; `mobile_dock_panel_test.dart` for the phone shell. | Done |
| While the bar is lifted, what floats just over it rises by `30 + foot / 2` (`[data-dock-lifted]`, `--dock-lift` on `.topic-timeline-float` and `ToEnd`, App.tsx diff 941 to 950). | `DMobileDockPeek.lifted` is true from the raise until the bar starts down, a pull takes it over, or the bar goes. `TopicCornerControls` adds `geometry.peek` to its bottom on its own 420ms `Cubic(.32, .72, 0, 1)`. `DPageHeaderGeometry.footerInset`, which places chat's jump to the present, rises through `DMobileDockLift` on the bar's spring, 460ms `Cubic(.3, 1.36, .5, 1)`, the mockup's `ToEnd` transition. Folded, the foot stays in its corner, as `[data-head-gone-0]` overrides the lift. | Saying tests for `DMobileDockLift` and `lifted`; the foot test lifts the shell's bar and measures the count rising by the peek and settling back. | Done |

### What a toast can carry, and how each is shown on a phone

The mockup's `toast(text, icon)` carries one line and a glyph, and lasts
2400ms. The app's `DToastOptions` also carries a title with a description,
an action (Undo after archiving a message or removing an assignment,
Refresh after a failed post change, Reauthorize for push), no timeout
(push prompts, and loading toasts from `promise`), a priority, custom
content, and an `onClose` listener. Callers also update a toast in place
by its id.

- A `sayable` toast is said by the bar for 2400ms, whatever its own
  timeout. It has a title or a description but not both, normal priority,
  a timeout, no action, no custom content, no close listener, and is not
  loading. Most of the app's toasts are this kind (`DToast.show`).
- Every other toast stays a card over the page, as before, where its action
  can be pressed, its loading state updated, and its close observed.
- The glyph follows the toast's type: success a check, info a circled i,
  warning a triangle, all in the accent; error a circled cross in the
  destructive colour. A standard toast has no glyph, because the app uses
  that type both for "done" and for "could not". The mockup's default is a
  check.


## Kit changes

1. **Floating tool pill parts** (the pill's ends). A tool button at the
   floating size inside a quiet joined group is content sized from 40 with
   12 insets, 15 at the group's ends, its glyph from the leading inset. This
   adds no option: the topic foot is the floating size's only joined tool
   group. Styleguide: Button group, "Floating tool pill".
2. **`DButtonDensity.dockRound`** (the count pill), and
   **`DMobileDockGeometry.circleOf`**, the dock's circle read with the
   dock's own text scale from inside reference chrome. On a phone the
   reading baseline makes the dock's circle 50.36 rather than 48, so the
   pill follows the circle rather than a number. Styleguide: Button, "Topic
   timeline actions".
3. **`DMobileDockPeek.say` and `sayToast`, `DMobileDockSaying`,
   `DSwipeHint.saying`, `DToastOptions.sayable` and `glyphOf`,
   `DToastController.teller`** (the dock says a toast). Its owner now
   disposes the peek. Styleguide: the mobile dock preview's action says
   "Draft started".
4. **`DMobileDockPeek.lifted`, `DMobileDockPeek.scope`, `maybeOf` and
   `liftedOf`, `DMobileDockLift`** (what floats over the bar lifts with it),
   and `DPageHeaderGeometry.footerInset` rising through `DMobileDockLift`.
   The shell's `MobileDockPanelScope` no longer carries the peek.
