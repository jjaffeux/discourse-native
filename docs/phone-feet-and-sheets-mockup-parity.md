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

## Sheets at the viewport foot

Phone bottom menus, forms, and reading sheets fill the viewport width and reach
its bottom edge. They have no exterior side or bottom gap. Each lower corner
uses the corresponding display radius when available. On iOS, where display
radii are unavailable, a bottom safe area selects the existing 55pt screen
curve. Explicit square display corners and screens without a bottom safe area
keep square lower corners.

The bottom safe area stays inside the sheet, below its content and fixed
actions. With a visible keyboard, the sheet surface continues behind it to
the screen edge. Only its content and fixed actions stop above the keyboard;
there is no exterior gap or rounded foot exposing the window ground there.
Menus retain their display corners behind the keyboard. Reading-page paint,
clipping, rims, and navigation share an outline whose bottom corners flatten
while the keyboard is visible. Adaptive menus keep their footprint through expansion,
scrolling, and loading changes.

The sidebar and composers retain `DMobileDockGeometry.endLift` and `endRadius`
for their own placement. At a 34pt foot, that lift is 23pt.

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
so the same form serves the desktop dialog. Desktop keeps every dialog.
Both hold the title, what the sheet holds and its actions on one inset
from the sides, as the mockup does: 15 inside a phone's 17/13 zoom,
19.5pt on a 390pt phone, with the actions 14 above the foot, and 17 in a
desktop dialog, 16 inside its rim, with the actions 16 under what it holds.

Fixed actions use `DSheetFooter`. At a partial detent, Native reserves the
bottom safe area below the actions, inside the sheet. With the keyboard
visible, the footer follows the sheet directly above it. Bookmark, flag, fast-edit,
notification-schedule, and edit-history sheets keep their actions outside the
body's scrollable region.

On touch the backdrop and the grabber dismiss, where the dialogs refused
a barrier tap; `canDismiss` still refuses while a write is in flight. The
touch sheet keeps the generic "Dismiss sheet" barrier label, so Assign's
own label is not carried over. No rule is drawn under the title or above
the actions, as the mockup draws none; what the sheet holds starts right
under its title.

The poll, date, event, emoji, GIF and status sheets keep their standard
inset sheet rather than the menu sheet; moving them is not part of this
change.

## Frost under a see-through palette

Reference: `test-mobile-layout` at `9b59748`, `cd5cd18`'s `.menu-sheet` and
`.side-nav--cards .side-section > .side-section__head` rules. The mockup sets
`data-sheer` when `round((1 - paletteOpacity) * 30) > 0`.

`DFrost` (`lib/src/theme/frost.dart`) is the one owner of that
predicate. `ForumBackground.sheer` is `transparency / maxTransparency * 30`
rounded, the theme carries it as a `DFrost` extension beside
`ForumThemeEffects`, and the kit reads it from `Theme`, so sheets in the
overlay see it with no shell wiring. Zero means nothing frosts and nothing
builds a `BackdropFilter`. The frost is `blur(26px) saturate(1.3)`: a sigma of
26 composed with a 1.3 saturation matrix.

| Surface | Opaque palette | See-through palette |
| --- | --- | --- |
| Phone menu sheet (`DSheetContent` menu and adaptive menu, no caller fill) | `panelBackground`, no blur | Fill thinned by `round(sheer / 3)`% (the mockup's `--surface-menu`), backdrop frosted within the sheet's rounded outline |
| Sheet to write on (`extendBehindKeyboard`, the mockup's `.is-full`) | Solid | Solid, never frosted |
| Drawer card heading | Opaque `panelBackground` | Fill thinned by `sheer`%, laid once (a plain rectangle while held, the rounded card otherwise); while held (pinned) the rows under it are frosted over its full width |

The frost sits behind the fill, so the fill is not itself blurred. The OS
Reduce Transparency channel is gone from the app
([appearance](material-mockup-parity.md)), so there is no flag to honour;
`DFrost` follows the appearance opacity alone.

Covered by `test/frost_test.dart` (sheet frost iff sheer, writing sheet solid,
`ForumBackground.sheer`, the theme extension) and `test/d_sidebar_cards_test.dart`
(held headings frost iff sheer and lay their thinned fill once).

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
