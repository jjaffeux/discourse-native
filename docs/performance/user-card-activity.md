# Phone user card activity

The phone user card scrolls its identity section and its activity as one sheet.
Before this work the activity was a plain column in that scroll view. It built a
whole page in the frame the page arrived, while the sheet was resting with no
row on screen, and it kept every row it had ever built.

## What changed

`DSheetContent.slivers` adds lazily built content after a sheet's children in
its whole-sheet scroll. The sheet stays sized to its content. The activity is
built as slivers there, so a row exists only near the viewport and is released
once it scrolls away.

The first rows arrive while the sheet is opening, so they are built one a frame.
They sit below the rest line behind reserved height, so the resting card does
not move. Scrolling fills the rest at once. A history of four rows or fewer is
laid out at once, because an estimated height could nudge a card that does not
fill its sheet.

Each row widget is held until its item or category changes, so the loading flag
and a new page rebuild no row that is already built. When old pages are dropped
or restored above the reader, the row being read is found again by its index.

The card ignores notifications from other cards' requests. Those notifications
cover every card on every forum, and each one used to rebuild the whole sheet.

## iPhone measurements

Each comparison uses five alternating profile-mode runs of each build at 120 Hz.
Each run opens eight cards with cold feeds. A fake API delivers each page after
250 ms, and the fixture carries real fonts and realistic rows. Half of the rows
have a cached topic, which is the costlier footer.

The table gives the worst UI-thread frame: the median over eight cycles in each
run, then the median of the runs. The budget at 120 Hz is 8.33 ms. The first two
columns are one comparison and the last two are another, so read each pair
against itself.

| Worst frame | Column of every row | One row a frame | One row a frame | Slivers |
| --- | --- | --- | --- | --- |
| Activity arrives | 48.8 ms | 6.0 ms | 6.0 ms | 6.7 ms |
| Next page lands at the list's end | 60.4 ms | 6.2 ms | 6.4 ms | 10.7 ms |
| Sheet rises | 5.3 ms | 0.9 ms | 0.9 ms | 0.8 ms |
| Scroll before the next page | 4.9 ms | 6.4 ms | 6.4 ms | 5.4 ms |
| Scroll after the next page | 9.7 ms | 6.6 ms | 6.6 ms | 5.3 ms |

After scrolling through two pages, the sheet holds 7 rows with slivers and 54
without. A column of every row held 60.

A page normally lands while the reader is still 1,600 points from the end, so
none of its rows are built on arrival. Three unalternated runs that scroll while
a third page lands peak at 6.4, 5.9 and 5.9 ms.

## Limits and tradeoffs

A reader who outruns the network sees the next page land on screen. That frame
builds the rows it reveals, peaks at 10.7 ms and exceeds the budget once per
card. It was 60.4 ms before any of this work.

Scroll raster median rises from 0.72 ms to 1.32 ms and p90 from 1.40 ms to 1.72
ms with slivers. Both stay well inside the budget.

The sheet's top-fade `ShaderMask` was a suspect and is not a limiter. Raster
stays near 1 ms through the rise and the scroll on this phone.

The [measurement data](data/user-card-activity.json) holds every run.

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
