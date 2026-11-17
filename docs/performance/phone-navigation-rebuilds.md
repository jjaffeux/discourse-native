# Phone navigation rebuilds

Opening a topic on a phone, going back from it, and opening or closing a menu
sheet over it each rebuilt large parts of the shell that do not change. This
note covers four of those parts. [Modal sheet backdrop](modal-sheet-backdrop.md)
covers the receding page beneath a sheet.

## What rebuilt

Rebuilt elements were counted with `debugOnRebuildDirtyWidget` in the phone
shell fixture of `test/support/topic_sheet_scroll_fixture.dart` on Android.
Each count is of elements that existed before the action and were built again,
grouped by the element whose own change started the rebuild.

- A menu sheet changes whether its page's route is current. `TopicView` and
  `DHistoryTransition` asked `ModalRoute.of` for that from callbacks, which
  made each depend on every status change of the route. The reader rebuilt
  about 460 elements and the page frame about 490 as a sheet opened and again
  as it closed.
- Each tab's root page stays mounted behind the other tabs. Chat's root page
  rebuilt its body, about 310 elements, on every forum navigation.
- The inbox workspace dropped its retained list pane whenever its widget
  updated, so opening or leaving a topic rebuilt the list pane down to its
  rows, about 640 elements.
- The topic list selected the open topic, so the whole list, about 440
  elements, rebuilt for the separators and keyboard highlight beside it.

## What changed

`DRouteScope` holds the route at the root of the home route's page. Below it,
`DRouteScope.routeOf` answers with the route without depending on its status,
and `DRouteScope.statusOf` announces status changes to listeners. The page
frame resets a swipe through that announcement, and the reader checks its
route through `routeOf`. Elsewhere `routeOf` is `ModalRoute.of`.

A tab's root page follows only the navigations that show its tab or leave it.

On a phone the workspace keeps its list pane while the values the pane reads
stay the same: the site, tab, connection, list route, layout, registry and
account. Opening or leaving a topic changes none of them. Touch screens draw no panel tabs, so the
list pane no longer switches its empty tab strip as a topic opens.

The topic list keeps the open topic in a notifier that its rows and separators
listen to, so a topic opening redraws the open row and the rows beside it.

## Measurements

| Elements rebuilt on Android | Before | After |
| --- | --- | --- |
| First frame of opening a topic | 1,631 | 1,053 |
| First frame of going back | 1,631 | 1,053 |
| Opening a menu sheet, all frames | 1,711 | 660 |
| Closing a menu sheet, all frames | 1,731 | 661 |

On iOS the first frame of opening a topic goes from 2,148 to 1,879, and a menu
sheet from 1,706 to 659 opening and from 1,726 to 660 closing.

Timings come from `integration_test/topic_sheet_open_profile_test.dart` on the
Android 16 ARM64 emulator with host GPU rendering, with profile builds of
baseline `c81ebe11c` and the change, two alternating runs of each. The table
gives the median of the repeated actions. UI time is a frame's build, layout
and paint duration.

| Longest UI frame | Baseline | Change |
| --- | --- | --- |
| Opening a menu sheet | 5.1 ms | 3.1 ms |
| Closing a menu sheet | 5.6 ms | 3.0 ms |
| Going back from a topic | 8.8 ms | 7.7 ms |
| Opening a topic | 12.5 ms | 12.3 ms |

The first frame of opening a topic barely moves. It builds and lays out the
new reader, about 830 new elements, and the rebuilds removed from it took
little of its time on this host. Raster totals moved between about 170 and
340 ms per opening across runs of the same baseline build, so they do not
measure this change.

## Measured but not changed

- The phone chrome rebuilds about 460 elements on each navigation. One
  selector over the route, the history entries and the reply state rebuilds the
  dock, the headers and the history gestures together.
- The sidebar's panel tabs rebuild about 100 elements on each shell
  notification, because Chat's panel listenable includes the shell.
- The three list rows around the opened topic rebuild, about 220 elements,
  because their highlight changes.
- `RouteAwareSelectionArea` still swaps its selection area as a sheet covers a
  topic, about 150 elements in the reader.
- On iOS the list pane moves beneath each topic sheet with its global key, so
  it is reactivated and rebuilds about 1,200 elements as a topic opens and as
  it closes. Android keeps the list in the topic sheet's source slot.
- Raster time did not change here. Skipping the history transition's
  transparent color filters left raster time within its run-to-run spread, so
  the engine already elides them, and that change was dropped. On a phone most
  raster time went to the lists' edge fades; see
  [Scroll fade backdrop](scroll-fade-backdrop.md).
- The first frame of opening a topic is mostly the reader's own first build
  and layout.

## Reproduce

Count rebuilds with a widget test that records `debugOnRebuildDirtyWidget` over
`pumpTopicSheetScrollFixture`, as `test/phone_sheet_rebuild_test.dart` does.
Time the actions with the harness in
[Modal sheet backdrop](modal-sheet-backdrop.md#reproduce).

## Verification

`test/phone_sheet_rebuild_test.dart` checks on Android that opening a topic
redraws only the rows whose selection changes and leaves Chat's root page
alone, and on Android and iOS that a menu sheet rebuilds neither the reader nor
the page frame. Each of those checks fails when its change is reverted.
`test/ui/d_route_scope_test.dart` checks that a page under the scope reads its
route status without rebuilding. `test/d_history_transition_test.dart` checks
that covering a route returns a swiped page at once, with and without a scope.
