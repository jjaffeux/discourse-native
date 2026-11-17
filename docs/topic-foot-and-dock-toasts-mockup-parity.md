# Topic foot and dock toasts parity

Reference: `discourse-native-mockups` at `540cbac` (branch
`test-mobile-layout`), from its message: "the topic's foot tools in pills by
the dock, its count as the timeline says it; toasts said by the dock as it
lifts, what floats over it lifting too". The rules are `.topic-foot-tools`,
`.topic-timeline-float`, `[data-dock-lifted]` and `.dock-says` in `app.css`;
`PostCount`, `TimelineMenu`, `TopicActionsButton`, `LevelButton`,
`toastStore`, `toast`, `floatToast`, `liftDock` and `ToEnd` in `App.tsx`.
Line numbers below are of `git show 540cbac` for each file.

The application UI goes through the Native kit, which this round may not
extend on its own (`AGENTS.md`). Rows marked Needs decision are the ones that
cannot be reached with the kit as it stands; each names the kit change that
would reach it.

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
| The end parts of the pill padded 15 so they look centred in its curve (app.css `> * > button:first-child`, `> :last-child`). | The kit's joined tool group gives every part the floating preset's 12 inset. | Not reachable. | Needs decision |
| Where you are is a pill as tall as the dock's circle (48) with 18 inline padding, and the foot row as tall as that circle (app.css `.topic-foot-tools`, `.topic-foot-tools .topic-timeline`). | `TopicProgressButton` stays on `DButtonSize.floating`, 40 tall with 12 insets. | Not reachable. | Needs decision |

Capture: `flutter test --dart-define=TOPIC_FOOT_CAPTURE_DIR=<dir>
test/topic_foot_tools_mockup_parity_test.dart` writes the phone screen per
platform. `topic-foot-and-dock-toasts-mockup-parity/topic-foot-iOS.png` and
`topic-foot-android.png` are the current ones.

## Toasts said by the dock

| Mockup change | Native | State |
| --- | --- | --- |
| On a phone a toast is said by the bar: lifted as for its peek, the toast's icon in the accent and its text at 13px medium strong where the hint goes, on one line with an ellipsis, for 2400ms, then the bar settles (App.tsx diff 176 to 208, 1489 to 1587, 1604 to 1632; app.css `.dock-says`). | Toasts are `DToaster` / `DToastController`, cards over the page; the peek and its hint are private to `DMobileDock`. | Needs decision |
| A bar folded into its circle is brought back first; under a sheet or the grown bar the toast waits, retrying every 150ms up to 30 times (`toastStore.dock` effect). | As above. | Needs decision |
| Only a layout with no bar floats the toast over the page (`floatToast`). | Every toast floats today. | Needs decision |
| While the bar is lifted, what floats just over it rises by `30 + foot / 2` (`[data-dock-lifted]`, `--dock-lift` on `.topic-timeline-float` and `ToEnd`, App.tsx diff 941 to 950). | The lift is `DMobileDockGeometry.peek`, but the dock exposes no lifted state; `TopicCornerControls` and `DMessageScroller`'s jump button cannot follow it. | Needs decision |

## Kit changes these need

1. **Foot count pill.** A `DButtonDensity.footCount` (or a
   `DControlSize.dockRound`) preset: `DMobileDockGeometry.circle` tall,
   18 inline insets, pill shape, label drawn as given. `TopicProgressButton`
   uses it on a phone, and `TopicCornerControls` takes its height, so the
   folded row lines up on the circle as `--float-half` now does.
2. **Joined tool ends.** `DButtonGroup.tool` gives its first part a 15
   leading inset and its last part a 15 trailing inset, through
   `DJoinedControlScope.first` / `last`, which the scope already carries.
3. **The dock says a toast.** `DMobileDockPeek` gains
   `bool say(DMobileDockSaying saying)` (icon, text, duration 2400ms): the
   dock holding it runs its peek lift with a `DSwipeHint`-sized line of the
   accent icon and 13px medium text in place of the hint, waits while it is
   out, covered or a sheet stands over it (150ms, 30 tries), asks
   `DScrollChrome` to reveal a folded footer first, and answers false when no
   dock can say it. `DToastController` gains an optional `teller` callback
   that `add` tries before queueing a card; `MobileShell` sets it from the
   session's peek, so a wide layout keeps floating cards.
4. **The lift for what floats over the bar.** `DMobileDockPeek` exposes a
   `ValueListenable<double> lift` (0 to `geometry.peek`, on the settle
   spring) that `TopicCornerControls` adds to its bottom and
   `DMessageScroller`'s jump button adds to its own.
