# Mobile swipe navigation

The phone shell separates sidebar access from Back by the gesture's starting position.
`DHistoryTransition` owns recognition and interactive page motion, including motion over retained reading sheets.

## Gesture regions

In a left-to-right layout, the sidebar corner is the first **80 logical pixels from the left** and **56 logical pixels below the top safe area**.
The upper bounds are exclusive. A touch at x = 80 or y = 56 belongs to Back.
The corner mirrors to the top-right in a right-to-left layout, along with the swipe direction.

For a phone with a 44-point top safe area, the sidebar region is x = 0 through 79 and screen y = 44 through 99.
The region covers the menu button and nearby header space without extending deep into the reader.
The dimensions are a product choice, not an Apple or Android standard.
Logical pixels correspond to iOS points and Android density-independent pixels, regardless of display pixel density.

The shell uses these rules:

- A rightward swipe starting in the corner opens the sidebar from any page, including a reading sheet.
- A rightward swipe elsewhere goes back one visit. At the history root, it does nothing.
- Back from a topic, channel, direct message, thread, or board restores its previous visit. Returning to a list dismisses the sheet.
- Opening the sidebar preserves the current visit and its Back and Forward history.
- A leftward swipe from the trailing 48 logical pixels goes Forward, or closes an open sidebar.
- Descendant horizontal controls keep their gestures. Board columns remain horizontally scrollable. The board header and shared header accept Back.

The starting position and initial horizontal direction select the action for the whole gesture.
Moving out of the corner cannot turn sidebar access into Back.
Vertical scrolling, downward sheet dismissal, and multi-touch gestures do not commit horizontal navigation.
Travel of 64 logical pixels or a forward flick commits the action. Short drags and cancelled gestures restore the current page.
Reduced motion preserves these actions without moving the page.
The menu button and existing Back controls remain available.

## Research and rationale

Sources checked on October 28, 2026:

- [Apple's gesture guidance](https://developer.apple.com/design/human-interface-guidelines/gestures) treats side swipes as a navigation shortcut alongside a Back button. It recommends predictable behavior, direct feedback, and avoiding conflicts with system gestures.
- [Slack's workspace-switching instructions](https://slack.com/help/articles/1500002200741-Switch-between-workspaces) describe swiping right from Home to reach the workspace list.
- [Telegram's FAQ](https://www.telegram.org/faq) describes swiping right in the Android chat list to open the app menu.
- [Android's gesture-navigation guidance](https://developer.android.com/develop/ui/views/touch-and-input/gestures/gesturenav) reserves inward swipes at either physical edge for system Back. It describes selective gesture exclusions for conflicting controls.

Slack and Telegram establish a precedent for rightward access to navigation at a list root.
These sources do not specify a shared top-left rectangle or a split between corner navigation and Back across the rest of the page.
The 80 by 56 corner makes that split explicit in this app. Its width allows a start near the menu button without requiring the exact physical edge.
Keeping Back across ordinary content makes the gesture usable away from Android's system edge region.
The app does not add system gesture exclusions. Android may handle a swipe beginning at the physical edge as system Back.
Start near the menu button, inside the app, to use the sidebar shortcut.

## Ownership and verification

`DHistoryNavigation` supplies a navigation entry, an inert live preview, and an open callback.
`backSwipeAnywhere` enables Back across the `DHistoryTransition` frame.
The phone shell supplies these options and routes completed gestures through its existing history controller.
`DSheetViewport` continues to own downward dismissal. A second horizontal recognizer on each sheet would compete with corner navigation and risk popping two visits.
Plugins do not need to implement their own navigation gestures.

The component styleguide's **History transition** example demonstrates corner navigation.
Focused widget coverage lives in `test/d_history_transition_test.dart`, `test/mobile_shell_test.dart`, `test/mobile_topic_sheet_test.dart`, `test/mobile_chat_sheet_test.dart`, and `test/plugins/boards/boards_sheet_test.dart`.
