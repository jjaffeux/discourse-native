# Users route

The Users route is one wide virtualized table. A phone shows about 13 rows and a
desktop about 17, and a row costs about 400 elements. Before this work, every
state change on the page built all of those rows again.

## What changed

The host hands back the same `UsersPage` when its data compares equal. The
shell, search and directory controllers announce changes for every tab, query
and account, and most of those notifications have nothing to do with this page.

The filter field owns its text, so a keystroke rebuilds the field alone.

A virtualized `DDataTable` reuses a built row while the row's value, its index,
its selection and each column's cell inputs compare equal. A cell builder runs
in its own element, so a theme change still reaches a held cell. `UsersPage`
keeps one builder per metric column and replaces it only when the column or its
largest value changes, so a landing page redraws only the columns whose bars
were rescaled. Column widths are outside the cells, so dragging a column edge
lays rows out again without rebuilding them.

`DChartBar` is one render box instead of a clipped and aligned subtree, which is
seven elements fewer per metric cell. A mark that ends away from the track's
corners is drawn without a clip.

The group filter lookup no longer sits ahead of the rows. It is unpaginated and
only feeds one combobox, so it runs beside the columns request. A cold route
goes from three sequential requests to two before rows can appear.

## Rebuild counts

These come from a widget test of the hosted route with seven metric columns and
are deterministic. Each line counts every widget rebuilt by that action.

| Action | Phone before | Phone after | Desktop before | Desktop after |
| --- | --- | --- | --- | --- |
| One filter keystroke | 3,490 | 69 | 4,089 | 69 |
| Search state for another route | 3,459 | 1 | 4,058 | 1 |
| Shell notification | 3,467 | 9 | 4,066 | 9 |
| Another directory query loads | 3,459 | 1 | 4,058 | 1 |
| Reaching the end through two pages | 24,365 | 11,831 | 26,296 | 11,481 |
| Five column drag moves | n/a | n/a | 24,965 | 6,132 |

A row is 364 elements and 166 render objects on a phone, down from 429 and 224.
On a desktop it is 341 and 155, down from 402 and 210.

## iPhone timings

Worst UI-thread frame on an iPhone 15 Pro Max at 120 Hz, where the budget is
8.33 ms. Each figure is the median of five alternating runs per side, with five
cycles per run and a fake 120 ms latency per request. Both sides passed every
run and did the same work, 24 requests and 150 rows per cycle.

| Phase | Before | After |
| --- | --- | --- |
| Unrelated notification | 16.7 ms | 0.3 ms |
| Filter keystroke | 16.6 ms | 1.2 ms |
| Vertical scroll | 12.3 ms | 2.9 ms |
| Next page lands | 46.5 ms | 34.0 ms |
| Rows arrive for a new period | 46.2 ms | 41.4 ms |
| Search results land | 28.9 ms | 37.2 ms |
| Horizontal scroll | 3.7 ms | 3.5 ms |

The search landing is slower and its cause is not known. Every landing after
this work costs about the same, 36 to 40 ms in a traced run, and the search
landing was the one cheap landing before it. Burning the CPU during the
keystrokes that precede it did not reproduce the old figure.

## Limits

The frame in which a new period or search first shows rows still builds every
row on screen at once. The notification and keystroke paths are the ones this
work removes, and the arrival frame only gains the cheaper row.

A held row reports no change to the list holding it, so `DTable` tells the list
when its row count changes. Without that signal the scroll range stays short
and the Users prefetch requests every page.

## Reproduce

Point the iOS Profile configuration at a separate bundle identifier and drop its
entitlements first, because `flutter drive` uninstalls the app when it finishes.
Do not commit that change.

```sh
flutter drive --profile -d <iphone> --no-pub --no-dds \
  --driver integration_test/performance_driver.dart \
  --target integration_test/users_route_performance_test.dart
```

The report lands in `build/integration_response_data.json` under `usersRoute`.
`test/users_page_performance_test.dart` pins the behavior behind these numbers
without a device.
