# Mobile navigation transitions

This reference describes the phone shell's visit history, foreground content, and return paths.
Gesture regions and animation behavior are documented in [Mobile swipe navigation](mobile-swipe-navigation.md).

## State ownership

[`MobileNavigation`](../lib/src/shell/mobile_navigation.dart) owns the selected tab, visit identities, history position, and sidebar visibility.
A core tab starts at a content visit.
A plugin tab can start at a null visit that represents its own panel, such as Chat's channel list.

[`ForumTab`](../lib/src/models/forum_workspace.dart) stores document routes and metadata.
The active document can remain parked on its last route while a plugin panel is foreground.
`ShellTabContext.currentContent` reads that document.
An explicit `ShellTabContext.atContent(route)` reads a retained source route within the same document.
These document views preserve source pages beneath sheets and search.

[`ShellController.currentContent`](../lib/src/shell/shell_controller.dart) describes foreground content.
At a mobile plugin panel root, it returns null and `ShellController.contentStack` returns an empty list.
The parked document remains available through `activeTab` and `ShellTabContext`.
Shell chrome, unscoped search, and plugin navigation hosts use the foreground route.
Search inside a scoped desktop panel uses that panel's document route.

## Transition cases

| Case | Result |
| --- | --- |
| Select Topics, Messages, Users, or another core destination | The selected destination becomes the first content visit in a new journey. |
| Select a plugin panel | The plugin panel becomes the null root visit. Parked document content does not control its chrome. |
| Open a page from a plugin panel root | The page starts a content stack for that visit. Back returns to the panel root. |
| Open search | Search becomes a content visit. Its own editor and Back control replace the normal header and tab bar. |
| Open a topic, channel, or thread from search | Search remains beneath the child sheet, with its editor and result state retained. |
| Dismiss a child sheet | The preceding visit returns. A retained search becomes active again. |
| Close search | The preceding content visit or plugin panel root returns, with its own header and tab bar. |
| Back or Forward | The history position changes, then the shell restores the selected visit. Restoring a visit does not append another visit. |
| Open or close the sidebar | The current visit and its Back and Forward history remain unchanged. |
| Navigate after Back | The new visit replaces the forward branch. A new page from a plugin root does not inherit its parked document stack. |
| Switch tabs or reselect a core tab | The selected tab starts a new journey. Earlier visits from another tab are not Back destinations. |
| Reselect the current plugin panel | The panel root returns. Existing visits remain available through Forward. |
| Change site or account | The shell changes the history owner and discards visits from the previous owner. |
| Show a private or unavailable forum boundary | The boundary controls the displayed page. A parked search does not hide the boundary's navigation chrome. |

## Shared commands and dismissal guards

`ShellController.pushContent()` and `replaceCurrentContent()` publish document navigation.
Workspace navigation commands require an explicit push or replacement and commit the active mobile visit before notifying views.
Raw document writes only update persistence and tab normalization.
Metadata hydration explicitly refreshes the current visit, preserving its identity and Forward history, and cannot reveal a parked document.
Notifications publish state without inferring navigation or correcting the foreground pane.
Only explicit journey selection or owner restoration bootstraps visits from a document stack.
Ordinary navigation records the visits the user actually made.
`selectMobileDestination()` and `selectMobilePanel()` select tab roots.
`handleBack()` and `handleForward()` use `MobileNavigation` and restore its selected location.
Search controls and completed horizontal swipes call these same commands.

[`MobilePresentation`](../lib/src/shell/mobile_presentation.dart) derives the foreground route, per-visit predecessors, retained sources, and sheet/chrome policy from visit history.
[`MobileForumRoot`](../lib/src/shell/mobile_shell.dart) shares that value with header, dock, and content through one inherited scope.
The scope changes only when its presentation facts change; unrelated shell notifications do not invalidate retained content.
The content host in [`mobile_content_host.dart`](../lib/src/shell/mobile_content_host.dart) owns the source and search element keys.
It rebuilds route data through the corresponding `ShellTabContext` instead of keeping earlier permission, account, and busy-state snapshots.
Retained list lookup stops at a nonsheet page, and every projected route uses its own actual predecessor.
[`ForumSearch`](../lib/src/shell/forum_search.dart) uses the same foreground route for unscoped search activation and context.
Plugin route hosts receive foreground content and report visibility independently of the selected tab's plugin owner.

Both mobile geometry paths use one private page-sheet wrapper in the content host.
It captures the visit's `entryId` and calls Back only while that entry remains current.
Android keeps its stable source viewport and separate reader key; the other path keeps its visit-keyed viewport.
[`DHistoryTransition`](../lib/src/ui/components/d_history_transition.dart) cancels stale gesture completion when its entry, history, owner, or route changes.
These guards prevent an old animation from navigating a newer visit.

## Focused coverage

- [Mobile navigation transitions](../test/mobile_navigation_transitions_test.dart) exercises return paths through Chat, search, and child content.
- [Mobile navigation](../test/mobile_navigation_test.dart) covers visit identity, Back, Forward, branches, and owner changes.
- [Mobile shell](../test/mobile_shell_test.dart) covers shared chrome, tab selection, sidebar gestures, and restoration.
- [Search presentation](../test/search_presentation_test.dart) and [global search presentation](../test/global_search_presentation_test.dart) cover search state and activation.
- [Mobile topic sheets](../test/mobile_topic_sheet_test.dart), [mobile chat sheets](../test/mobile_chat_sheet_test.dart), and [board sheets](../test/plugins/boards/boards_sheet_test.dart) cover child presentation and dismissal.
- [History transitions](../test/d_history_transition_test.dart) covers gesture completion, cancellation, and history changes.
- [Voice navigation](../test/voice_navigation_test.dart) covers room links and repeated room activation.
