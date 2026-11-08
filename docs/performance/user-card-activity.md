# Phone user card activity

The phone user card scrolls its identity section and its activity as one sheet.
The activity shares the sheet's scroll view, so nothing virtualizes its rows.
Before this change it built a whole page in the frame that page arrived, while
the sheet was resting with no row on screen.

## What changed

The list builds one row a frame. The first eight rows fill in below the rest
line behind reserved height, so the resting card does not move. Later rows wait
until the reader scrolls within a prefetch distance of the end of what exists.
A history of four rows or fewer is laid out at once, because an estimated height
could nudge a card that does not fill its sheet.

A page is requested only once every row already held is built. The Load more
control follows the same rule.

Each row widget is held until its item or category changes, so the loading flag
and a new page rebuild only new rows. Each row also has its own layer. The sheet
scrolls by repainting all of its content, and those layers keep that repaint from
reaching rows already drawn.

The card ignores notifications from other cards' requests. Those notifications
cover every card on every forum, and each one used to rebuild the whole sheet.

## iPhone measurements

The comparison uses five alternating profile-mode runs of each build at 120 Hz.
Each run opens eight cards with cold feeds. A fake API delivers each page after
250 ms, and the fixture carries real fonts and realistic rows. Half of the rows
have a cached topic, which is the costlier footer.

The first table gives the worst UI-thread frame. It is the median over eight
cycles in each run, summarized as the median of the five runs with their range.
The budget at 120 Hz is 8.33 ms.

| Worst frame | Baseline | This change |
| --- | --- | --- |
| Activity arrives | 48.8 ms (46.0 to 52.3) | 6.0 ms (6.0 to 6.5) |
| Next page arrives | 60.4 ms (59.8 to 62.2) | 6.2 ms (5.8 to 6.3) |
| Sheet rises | 5.3 ms (5.0 to 5.6) | 0.9 ms (0.9 to 1.0) |
| Scroll before the next page | 4.9 ms (4.7 to 5.6) | 6.4 ms (6.0 to 6.5) |
| Scroll after the next page | 9.7 ms (8.6 to 10.5) | 6.6 ms (6.2 to 6.8) |

| Frames over budget per run | Baseline | This change |
| --- | --- | --- |
| Activity arrives | 8 | 1 (0 to 1) |
| Next page arrives | 8 | 0 (0 to 1) |
| Scroll after the next page | 10 (7 to 10) | 0 |

Median scroll build time falls from 1.44 ms to 0.72 ms before the next page, and
from 1.78 ms to 0.48 ms after it.

## Limits and tradeoffs

The worst scroll frame before the next page rises from 4.9 ms to 6.4 ms, because
that frame now also builds a row. It stays inside the budget. Scroll raster p90
rises from 0.90 ms to 1.42 ms with the per-row layers, against the same budget.

Rows that have scrolled past stay built, as they did before. A reader who pages
deep into a history still holds every row. Releasing them needs the sheet to
offer a sliver slot for its whole-sheet scroll, which the UI kit does not have.

The sheet's top-fade `ShaderMask` was a suspect and is not a limiter. Raster
stays near 1 ms through the rise and the scroll on this phone.

The [measurement data](data/user-card-activity.json) holds every run. The five
rounds predate two simplifications to how the card rebuilds, and one further run
after those simplifications matched these numbers. Only a closure that runs on
tap changed after that run.

## Reproduce

Point the iOS Profile configuration at a separate bundle identifier and drop its
entitlements first, because `flutter drive` uninstalls the app when it finishes.
Do not commit that change.

```sh
flutter drive --profile -d <iphone> --no-pub --no-dds \
  --driver integration_test/performance_driver.dart \
  --target integration_test/user_card_activity_performance_test.dart
```

The report lands in `build/integration_response_data.json` under
`userCardActivity`. `test/user_card_activity_performance_test.dart` pins the
behavior behind these numbers without a device.
