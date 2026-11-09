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

## iPhone baseline

Median of the worst UI-thread frame over five cycles, on an iPhone 15 Pro Max at
120 Hz. The budget is 8.33 ms. Latency is a fake 120 ms per request.

| Phase | Worst frame |
| --- | --- |
| Rows arrive for a new period | 46.6 ms |
| Search results land | 47.0 ms |
| Next page lands | 44.4 ms |
| Unrelated notification | 17.7 ms |
| Filter keystroke | 17.3 ms |
| Vertical scroll | 12.5 ms |
| Horizontal scroll | 3.8 ms |

The after run could not be taken because the phone went offline during this
work. Treat the rebuild counts above as the evidence for this change, not these
timings.

## Limits

The frame in which a new period or search first shows rows still builds every
row on screen at once. The notification and keystroke paths are the ones this
work removes, and the arrival frame only gains the cheaper row.

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
