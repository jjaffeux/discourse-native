# Phone feet and sheets parity

Reference: `discourse-native-mockups` at `847614e` (branch `test-mobile-layout`),
look A. The changes came in `f493c51` ("dialogs as sheets on a phone; sheets
at their end rounded with the screen's corner; … a chat's composer placed
against A's bar and level with its circle") and `ef17e47` ("a phone's
sidebar and rail as low as a sheet at its end, the card's foot rounded with
the screen's corner"). The rules are `.menu-sheet.is-end`,
`.phone-drawer__panel .side-nav`, `.chat-dock` and `.composer-min` in
`app.css`; `SHEET_END_GAP`, `MenuSheet`, `Sheet` and `composerBar` in
`App.tsx`.

## One rule for the foot

What ends at the screen's foot stands off it by the bar's 6 past half the
foot's room, and a corner there follows the screen's 55 curve from that far
in, never tighter than its own least radius. A square screen, and anything
over the keyboard, has no curve to follow. `DMobileDockGeometry.endLift`
and `endRadius` hold the rule. At width 390 and a foot of 34:

| Part | Value |
| --- | --- |
| Lift | `6 + foot / 2` = 23. With the keyboard up the foot is 0, so 6. |
| Foot corner | `max(least, 55 - lift)` = 32 on a screen with a foot; `least` without one. |

## Sheets at their end

| Part | Value |
| --- | --- |
| Adaptive menu at its end | Full width (no side inset), 23 off the bottom edge, top corners 22, bottom corners `endRadius(24)` = 32. The foot's room the lift leaves, `max(0, foot - lift)` = 11, stays inside the sheet. Lifting and its corner ease together on the sheet's own progress. |
| Over the keyboard | 6 off the keyboard, bottom corners 24. While the keyboard rises, the corner eases from 32 to 24 by the keyboard's placement rather than following the shrinking foot, which would swell it past both. |
| Inset menu sheet | The same placement at once: full width, 23 off the bottom edge, bottom corners 32, 11 of the foot kept inside. |

The sheets' shadows and edges belong to the shadows work, not to this one.

## Sidebar and rail

| Part | Value |
| --- | --- |
| Panel | 6 from the rail, the top and the screen's end; `6 + foot / 2` = 23 off the bottom edge. Corners 14 but for the outer foot corner, `endRadius(14)` = 32. |
| Rail | Its fill runs to the foot; its last control stays `foot / 2 + 10` = 27 above it. |

The navigation page no longer consumes the safe area as a whole; the panel's
content sees no bottom padding.

## Composers

| Part | Value |
| --- | --- |
| Topic composer's foot | The action strip stands `endLift` off the foot (23), or 6 off the keyboard; the footer itself keeps no bottom padding on touch. |
| Chat composer, open | 8 over the bar's top edge, the bar holding the foot's room itself (`bar-h + 6 - min(6, foot) + 8` in the mockup). |
| Chat composer, folded | Level with the bar's circle: `cornerAt(48)` from the bottom and the end, past the circle and 8 at the start, the circle's height. |

## Parked draft

| Part | Value |
| --- | --- |
| Place | 8 over the bar's top edge, 6 in from the screen's sides. The bar stays on the foot; it no longer lifts as a capsule over a parked draft. |
| Look | The resume card: 52 tall at the default scale, radius 16, `DTokens.wellFill` with the subtle edge. |
| Clearance | The shell's footer reserves the pill's height and 8 over the bar, so pages scroll clear of both. |
| In a chat | Hidden, since the chat's own composer stands there, and under the open sidebar. It stays mounted offstage, so the retained editor keeps its state. A route says it docks its own phone composer through `ContentMobileComposerPlugin`; Chat's conversations do. |
| No bar | A route that hides the bar keeps the pill at the foot, as before. |

## Dialogs as sheets on a phone

The mockup's `Sheet` returns a `MenuSheet` on a phone: grabber, the title
as a 15pt heading, no close button. Every use of it, and what opens here:

| Mockup sheet | Here, on touch |
| --- | --- |
| Edit bookmark, Edit history, Flag post, Flag topic | `showShellSheet`, already a sheet; now the adaptive menu. |
| Delete bookmark? | `_confirm` in `bookmark_ui.dart`: a sheet with Cancel and Delete, returning a bool. |
| Add / Change notice | `showPostNoticeEditor` through `showShellSheet`. |
| Change owner (a post, a topic's selected posts) | `showTopicChangeOwner` through `showShellSheet`. |
| Move posts | `showTopicMovePosts` through `showShellSheet`. |
| Assign / Reassign post and topic | `showAssignmentEditor` through `showShellSheet` below 768 on touch, in place of the drawer, the keyboard kept closed. |
| Set custom status | Already a touch bottom sheet. |
| Insert link | `showComposerLinkDialog` through `showShellSheet`. |
| Poll, Date in post, Event, Emoji, GIFs | Already touch bottom sheets. |
| Upload | The upload choice's `DDropdownMenu` opens its adaptive sheet on a phone. |

`showShellSheet` on touch is the adaptive menu, as every phone menu is: a
tall sheet opens at its lower height and is pulled up for the rest,
including a pinned footer, as the mockup's does. Its title row has no
close button; a nested sheet keeps its back button. `fillAvailableHeight`
there reserves the fixed opening height and takes the room above a
visible keyboard. A form whose body and actions the sheet builds apart
shares its state through `ShellSheetForm`, and closes with `DDialogClose`
so the same form serves the desktop dialog. Desktop keeps every dialog as
it was.

Fixed actions use `DSheetFooter`. At a partial detent, Native reserves the
bottom safe area below the actions. As the sheet floats upward, the footer
reserves only what the sheet's own lift and content inset have not covered.
The scrolling body keeps its viewport through the safe area. With the keyboard
visible, the footer follows the sheet above it. Bookmark, flag, fast-edit,
notification-schedule, and edit-history sheets keep their actions outside the
body's scrollable region.

On touch the backdrop and the grabber dismiss, where the dialogs refused
a barrier tap; `canDismiss` still refuses while a write is in flight. The
touch sheet keeps the generic "Dismiss sheet" barrier label, so Assign's
own label is not carried over. The divider under the title stays, though
the mockup's phone sheet has none.

The poll, date, event, emoji, GIF and status sheets keep their standard
inset sheet rather than the menu sheet; moving them is not part of this
change.

## Validation

`test/d_mobile_dock_geometry_test.dart`, `test/ui/d_sheet_adaptive_menu_test.dart`,
`test/ui/d_sheet_test.dart`, `test/mobile_shell_test.dart` (the navigation
panel's foot, the parked draft over the bar and out of a chat),
`test/composer_viewport_overlay_test.dart` (the composer's foot),
`test/composer_docking_test.dart` (the parked draft over the bar),
`test/chat_shell_integration_test.dart` (the chat composer against the bar),
and for the dialogs `test/shell_sheet_test.dart`,
`test/post_notice_editor_ownership_test.dart`,
`test/topic_change_owner_ownership_test.dart`,
`test/topic_move_posts_ownership_test.dart`,
`test/composer_link_dialog_test.dart`, `test/bookmark_ui_test.dart`,
`test/assignment_sheet_test.dart`,
`test/assignment_picker_session_boundary_test.dart` and
`test/composer_upload_panel_test.dart`, with `test/support/phone_sheet.dart`.
Each new test fails with its change undone.
