# Phone bar parity

Reference: `discourse-native-mockups` at `9b59748` (branch `test-mobile-layout`),
look A. The rules are in `app.css` under `[data-variant="a"]` and `.dock-float`;
the place order is `dockDests` in `App.tsx`, the bar's row `dockSide`,
`dockItemsAt` and `NavBtn`, and the unread chip `UNREAD_CHIP`.

## Places

The bar and its panel are a phone's Start page, so Start is not a place.
Its order is Topics, the plugin panels (Chat), Bookmarks, Dashboard (staff),
Inbox, Users, the community shortcuts, Categories, Groups, Badges, Settings
and Preferences. Next come the places only the Start page used to offer:
Summary, Activity, the sections plugins contribute to Start (Chat's Channels
and Threads), and Drafts, which appears only while a draft can be resumed.
`_mobilePlaces` in `mobile_shell.dart` holds this one list. The dock, its
panel, the history gestures' tab order and the fallback for a selection that
is no longer offered all read it. A person may put the places in their own
order by holding one in the panel (see Moving a place below);
`MobilePlaceOrderController` keeps that order per forum account and
`_mobilePlaces` applies it before anything reads the list.

Notifications is not one of these. Once signed in it is fixed in the bar as
the last place before the action (`DMobileDock.notifications`,
`_notificationsPlace` in `mobile_shell.dart`): the inbox glyph the header's
bell used, named Notifications, counting what has arrived for the active
site since the menu was last open (`UserMenuButton.unreadCountOf`, the
bell's own count) and hiding the count while the menu is open. Pressing it
toggles the notifications menu, which the phone's header still hosts as
`UserMenuButton(presentation: UserMenuPresentation.dockNotifications)` with
no bell of its own: the top bar's bell is a desktop's alone. Signed in, the
header hosts it beside its row rather than in it, so it takes no room there:
Search ends at the header's 14-point end inset, and with large text there is
no second row of actions. Signed out, it draws the sign-in actions, which the
row lays out after Search. While the menu
is open the bar marks Notifications as it marks the current place. It is
never lifted to be moved, is no slot for a place being moved, and never
moves into the panel.

## Geometry

`DMobileDockGeometry` is one pure value computed from the screen's foot (the
bottom safe inset, which is 0 while the keyboard is up) and the text scale.
The dock, the shell's footer, `DComposerDock`, the topic timeline, the phone
sheets, the sidebar and the composer's foot all read it. At width 390, a foot
of 34 and the default scale:

| Part | Value |
| --- | --- |
| Bar on a round screen | Full width, no side or bottom margin. Top corners 31, bottom corners square. Padding 6 at the top and sides and `6 + min(foot, 55 - 31)` = 30 at the bottom. 86 tall. |
| Bar on a square screen | The floating capsule, 6 in from every edge. A parked draft waits over the bar rather than lifting it ([feet and sheets](phone-feet-and-sheets-mockup-parity.md)). |
| Footer pages clear | The bar plus its 6 top margin, 92. |
| Columns | `(inner - 4 * 4) / 5` = 72.4, with a 4 gap. The first three places take one each, Notifications the fourth, the action the fifth. |
| Action | 50 across, its middle 37 in from the screen's end edge (`--dock-action-in`): from 322 in the row. On a capsule that is the row's end, as before. A bar too narrow for it widens the last column and the others share what is left (`rowSlots`). Grown, it travels to the fifth column's middle. |
| Closed bar | The places are their glyphs alone, centred on the row and named to a reader; a place's count rides its glyph's corner, 6 below the place's top with its start edge 6 past the column's middle (`DMobileDockItem.bare`). Grown, the names come back and a count sits beside its name. |
| Current page past the third place | Added to the bar before Notifications, the five sharing the four columns' room equally: `(4 * 72.4 + 3 * 4 - 4 * 4) / 5` = 57.12 each, the gaps kept. It is marked current and pressing it grows the bar. Grown, it eases away on the panel's settle spring, its width to 0 and the gap after it with it, its opacity over 200 ms, and the places after it return to their columns. |
| Current-place mark | 28 × 4 on the bar's top edge, bottom corners radius 3, in the foreground colour. Grows in over 200 ms. Over the current place, over the page added for it, and over Notifications while its menu is open. The current place has no fill. |
| Folded circle and topic timeline | Each sits on its corner's diagonal, `cornerAt(e) = max(6, min(55 - (55 - 6 - e/2) * 0.7071 - e/2, foot))` from both edges. That is 13.32 for the 48 circle and 15.37 for a 34 tall control. |
| Fill | `DTokens.wellFill`, the palette background with Oklch lightness lowered by 0.08. On a phone the plain ground is the same colour. |

The literal 55 stands for the screen corner radius the mockup assumes. The
app does not read the device's real radius. There is no ⋮ on a phone's bar.

## The unread chip

What is unread in a place is one chip, `DBadge.unreadChip`, wherever a place
is counted: a place's count in the bar (Chat's urgent count), Notifications'
count, and Chat's count on the sidebar's Forum / Chat switch (see
[sidebar switch parity](sidebar-switch-mockup-parity.md)). It is the mockup's
`UNREAD_CHIP` and `[data-touch] .nav-btn__count`: a pill of the success colour
struck a quarter into the ground (`--success-fill`), its figures the success
colour struck halfway into the text (`--success-fill-text`), tabular and
centred, `99+` past 99. On a desktop it is at least 17 wide, 16 tall, 4 inside
each end, 11/700 on a 16 line; on a phone the size of the list's counts, at
least 20 wide, 20 tall, 7 inside, 12.5/600 on a 20 line. It keeps the
reference text scale as the list's counts do. Beside a grown place's or a
panel tile's name it keeps that height, centred on the name's 14 line and
overhanging it, and the name does not move for it. Chat with nothing urgent
keeps its dot.

## The panel

A pull up on the bar, or a press on the page added to it, grows the bar into a
panel of the places past its columns, with you as the last tile when signed
in. The bar also takes a trackpad's two-finger swipe, to grow and shrink, and
a screen reader's "More places" and the keyboard's Arrow Up, which draw
nothing (see Keyboard and screen readers below). The
rules are `.dock-float`, `.dock-panel` and `.dock-panel-dim` in `app.css`,
and `growTo`, `growDrag` and the trackpad effect in `App.tsx`.
`DMobileDockPanelGeometry` holds the arithmetic and `DMobileDockDrag` the
settle rule; `DMobileDock` owns the growth as one of closed, dragging,
settling and open, driven by an `AnimationController` so a drag repaints the
dock and the panel alone. At width 390, a foot of 34, the default scale and
six tiles:

| Part | Value |
| --- | --- |
| Panel | Full width from the screen's foot, `wellFill`, top corners 31. Five columns of `(width - 12 - 16) / 5` = 72.4 with a 4 gap, rows 56 with a 14 gap. 92 above the grid (16 for the grabber, the bar's 6, its row as a 56 tile, a row gap), the foot + 8 below. Two rows: 260 tall; one row of up to five: 190. |
| Reveal | `(1 - g)` of the 174 above the bar's top edge is cut off the panel's top. The bar rises `g * 158`, leaving 16 for the grabber. The grid's opacity is `clamp(1.6 g - .6)`. |
| Grabber | 36 × 5, radius 3, `subtleMark`, 6 below the panel's moving edge. A button named "Fewer places", its expanded state the panel's, that puts the panel away; drawn that small, the kit's 44 touch area applies. |
| Settle | `Cubic(.3, 1.36, .5, 1)` over 460 ms for growth, which may pass open or closed and come back; the dim and the grid ease over 300 ms. Nothing animates under reduced motion. |
| Dim | Black at `.32 g` over the whole screen, under the panel and the bar. A pointer down on it closes the panel. |
| Tiles | 56 tall, radius 16, hover `foreground` at 8%, the current one `foreground` at 10% (the mockup's `--primary` is its text colour), icon 18, name 11.5 in `mutedForeground`, 600 and `foreground` when current. |
| Head | The bar's fill goes transparent and its places are tiles like the grid's, named again, the current one lit `10% g`, icons scaled `1 - .1 g`. The mark fades at `1 - 2 g`; the page added to the bar eases away and the rest return to their columns. The action moves to the centre of the fifth column, its circle fading, its icon risen 8 and in `primary`, its name 11.5 under it, 39 below its top, at most `72.4 - 8` wide on one line, cut short. |
| You | A 22 face with a 1.5 ring set 1.5 outside it: `success` when present, `subtleMark` when notifications are paused, none otherwise. Named as the account menu names you; opens the header's account menu. |
| Drag | Slop 8; a touch starting within 20 of the screen's bottom edge is the home gesture's. `g = start + dy / 174`. Released, a flick past .1 px/ms goes its way; still, from a start short of halfway (closed, or where the peek had lifted the bar) it opens past .25, and from past halfway past .75. The velocity is read over the last 100 ms of samples. |
| Trackpad | A swipe moves `g` by its travel over 174 and settles 180 ms after it stops, opening if it moved up past .02 and closing on a push down unless it stayed past .98; momentum within 160 ms of settling is ignored. |

The panel is an `OverlayPortal` from the dock, so it paints above the
header and the page and below the sheets opened after it. Escape, the
system back, a press on the dim, the grabber, a place in the head
(Notifications among them, which then toggles its menu), the action and a
tile close it; it is put away with the bar, at once, when a composer's
sheet covers the shell, the scroll chrome hides the footer or the sidebar
takes the bar, and a dock taken out of the tree while out tells the shell
the panel is in. The focus moves to the first tile once the panel is meant
to be open, pressed open or let go to settle open, and not under a finger;
on closing it goes back to what had it, or else to the page added to the
bar, which opened it, or else to the bar's first place. The keyboard goes
round the grabber, the head's places, Notifications, the action, the grid
and you, with the page added out of the round while the panel is out.

### Keyboard and screen readers

A person who cannot pull the bar has two ways in. Neither draws anything or
changes a place's room or target, and the mockup has neither, its bar being
pulled. While the bar can grow and is not out, every place in it,
Notifications and the page added among them, offers a screen reader the
custom action "More places", which grows the bar as a press on the page
added does (`_readerActions`). It is on each place rather than on the row,
as VoiceOver's actions rotor and TalkBack's actions menu list the actions of
the element a reader is on, and a reader is never on the row itself. Out, the
same places offer "Move earlier" and "Move later" instead, and the grabber's
"Fewer places" puts the panel away. With the focus on any place of the
closed bar or on its action, Arrow Up grows the bar rather than moving the
focus up to the page; a bar that cannot grow leaves Arrow Up to the page.
Either way in, the focus moves to the first tile, as for any growth meant to
be open, and goes back to what had it as the panel closes, so the place or
the action Arrow Up was pressed on has it again.

Out, the arrows move the focus between the grabber, the head and the grid's
rows, as they do anywhere in the app, so Arrow Down does not close the
panel. Bound to closing, it could no longer take the focus from the head
into the grid or from one row to the next. Escape closes it. A place the
keyboard has focused shows the kit's tooltip, which takes the first Escape.

### The peek

Nothing in the bar itself says it can be pulled up, so on opening it says
so once: `DOCK_PEEK_AFTER`, `DOCK_PEEK_FOR`, `endPeek` and the peek effect in
`App.tsx`, and the `.dock-float[data-peek]`, `.dock-panel__hint` and
`@keyframes dock-hint-shine` rules in `app.css`. The once is the mockup's
`peeked` ref: a `DMobileDockPeek` the phone shell keeps for as long as it
stands (`_MobileShellState`, handed down through `MobileDockPanelScope`), so
a bar built again, as the sidebar gives it back, does not peek again. The
first `DMobileDock` given it with places past its columns takes it, and is
the one to peek or not. `DMobileDock` draws the peek in the overlay the
panel uses, the panel and the bar alone, with no dim, no modal semantics and
nothing catching the page's touches; the slot keeps the bar's room and the
page's lists still thin under it. At width 390 and a foot of 34:

| Part | Value |
| --- | --- |
| When | `DMobileDock.peekAfter`, 900 ms after the bar first has a panel to grow into, unless by then it cannot grow (folded, its places hidden, covered, the footer away) or is out under a finger, a swipe or open. Taken either way: it never comes again in that session. |
| Up | The bar lifts `DMobileDockGeometry.peek`, `30 + foot / 2` = 47, on the settle spring, `Cubic(.3, 1.36, .5, 1)` over 460 ms, passing its lift and coming back. Its fill is left to the panel's. The panel shows under it from the screen's foot to the bar's lifted top, `wellFill`, top corners 31, on the same spring; no grabber, no grid, no dim. The bar stays a closed bar: glyphs alone, its mark on its top edge. |
| Hint | "Swipe up for more", 13 / 500, centred in a box the screen's width whose bottom is `foot / 2` = 17 above the screen's bottom and whose height is `peekUnder + peek - foot / 2` = 75, where `DMobileDockGeometry.peekUnder`, 45, is how far the bar's glyphs' bottom stood above the foot before the lift: the box runs from half the foot to the lifted glyphs. In 150 ms after up: its opacity over 200 ms and a rise of 6 over 300 ms, both `ease`. Out with no wait: 200 ms and 300 ms, `ease`. Not read to assistive technology. |
| Light | A gradient at 100° over three times the text's width, `mutedForeground` to 34%, `foreground` at 50%, `mutedForeground` from 66%, slid from its end to its start over the text in 1.6 s, linear, from 300 ms after up and again each 1.6 s while up. Mirrored for a right-to-left reader. Back to its start, all muted, as the bar goes down. |
| Hold and down | Up for `DMobileDock.peekFor`, `300 + 2 × 1600 + 200` = 3700 ms: two passes of the light and the start of a third. Then down on the same spring, the hint going, and the peek is over once the bar is back down. The mockup clears its `data-peek` 480 ms after down, just past its 460 ms transition, as its `growTo` clears `data-easing`; the app ends both on the animation's own end instead, so nothing of the peek is left once nothing moves. |
| Taken over | A pull past the slop, a trackpad swipe, or a press, a screen reader's "More places" or Arrow Up growing the bar ends the peek and carries on from where the bar is: the growth starts at `lift / max(1, travel)`, 47 / 88 with three tiles and 47 / 158 with six, so the bar does not jump. The hint goes as it would have, in the grown panel's foot, and is gone 300 ms later. |
| Taps | A place pressed during the peek is pressed as ever, where it has been lifted to; the panel under the bar takes a pull and nothing else. |
| Reduced motion | The same steps at the same times, at once, with no light. |

`DMobileDock` owns the peek as one of none, up and down beside its growth,
on its own lift controller and a clock for the light; a step of the peek
rebuilds the dock alone and a frame of it repaints the layer alone. Where
the mockup leaves a docked or grown bar's panel clipped to the peek until
its timer runs out, the app ends the peek at once: a bar put away, or grown
by a press on the page added to it, takes the peek with it.

### Moving a place

A place in the open panel, in its grid or in its head, is moved by holding
it: `navHold`, `navPlaced` and the `[data-lifted]` and `[data-reordering]`
rules in the mockup, with `growDrag` yielding to a lifted place.
`DMobileDockReorder` holds the values and the slot arithmetic,
`DMobileDockPanelGeometry.placeRects` the slots, and `DMobileDock` owns the
move as one of still, lifted and dropped, drawn in the panel's own box over
the bar while the places' own tiles keep their room, keys and focus unseen.
`MobilePlaceOrderController` keeps the order.

| Part | Value |
| --- | --- |
| Hold | Still for 320 ms. Moved past the bar's slop of 8 before then, in any direction, the hold is given up; a vertical move is the panel's drag as before. Only while the panel is open, and only a place: Notifications, the action and you are not slots. A light haptic marks the lift. |
| Lifted | The tile follows the finger exactly, held by the point it was grabbed at, across the bar and the panel, scaled 1.06 over everything else in the panel, on `raisedBackground` with radius 16 and a `0 8 24` shadow of black at 35%. The panel's drag and a trackpad's swipe are suspended until release. The bar's mark is hidden, as it is whenever the panel is open, and what cannot be moved, Notifications and the action, steps back to opacity .4 over 200 ms. |
| Slots | Taken once, at the lift, from the geometry rather than from the sliding tiles: the head's three columns, then the grid's cells. Notifications' column is no slot. A slot is hit only inside its inner 70%. Hitting slot *i* puts the place at *i* in the full order and the rest close up, each sliding from its old slot to its new one over 220 ms on `Cubic(.32, .72, 0, 1)`. |
| Let go | The place settles from where it is into its slot over 200 ms on the same curve, shrinking back, and the release presses nothing. The panel closing under a lifted place sets it down unmoved, and so do the places coming in any order but the one it was lifted from. Nothing animates under reduced motion. |
| Order | `onMoved(from, to)` is told once per move, and the shell writes the shown order as a list of `MobileTab.name`s, per forum account, through the serial preference queue; a stored name not shown at the time, Drafts between drafts, keeps its place after the one before it (`MobilePlaceOrderController.placed`). Placed names come first in their saved sequence, the unplaced follow in their default order, a name the forum no longer offers is dropped, and a place offered anew takes its default position among the unplaced. |
| Screen readers | While the panel is out, every place but the first offers the custom action "Move earlier" and every place but the last "Move later", each a move of one slot told through the same `onMoved`. Notifications, the action and you offer neither. A screen reader cannot press and hold, and the mockup has no equivalent. A place moved within the grid or within the head is the tile it was, the same node to the reader and still the one with the focus; the focus the panel took follows its place between the two. |

A lift, a frame of the follow and a slot change repaint the dock alone;
only the move told as the place is let go rebuilds the shell's chrome,
through the place list.

## Validation

`test/d_mobile_dock_geometry_test.dart`, `test/d_mobile_dock_growth_test.dart`,
`test/d_mobile_dock_reorder_test.dart`, `test/mobile_place_order_test.dart`,
`test/d_mobile_dock_test.dart` (the peek, and the ways in for screen readers
and the keyboard, among it),
`test/d_mobile_dock_item_test.dart`,
`test/d_badge_test.dart` (the unread chip), `test/d_composer_dock_test.dart`,
`test/oklab_test.dart`, `test/topic_progress_motion_test.dart`,
`test/mobile_shell_test.dart`, `test/mobile_dock_panel_test.dart`,
`test/sidebar_panel_tabs_test.dart` (the chip on the sidebar's switch) and
`test/mobile_dock_panel_backdrop_test.dart`. Tests grow the bar through
`openDockPanel` in `test/support/dock_panel.dart`, a pull on the bar, as a
phone's bar has no ⋮.
