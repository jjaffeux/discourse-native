# Topic-list scrolling

The list was already virtualized, and ordinary scrolling did not rebuild
existing titles or the list shell. Fast scrolling exposed two configuration
problems: offscreen cache rows were built on every frame and discarded on the
next, and each 1-pixel separator was estimated at the library default of 100
pixels. CPU samples showed allocation/garbage collection, element mounting and
deactivation, and row layout. Scroll-position bookkeeping was small: its median
95th percentile was 10 microseconds in the baseline.

The fix enables `delayPopulatingCacheArea` and gives separators a 1-pixel
estimate, with the normal minimum row height as the topic estimate. Actual row
heights remain variable. The existing Diagnostics → Topic scroll recorder now
also records topic-list row builds, list rebuilds, scroll geometry, visible
ranges, and scroll-handler cost. It does no per-event recording unless armed.

## Native measurements

Implementation: `8256b60b`. The baseline uses the same instrumentation and
fixture with the two list configuration properties omitted. Three alternating
baseline/fixed runs used macOS profile mode, Skia on Metal, a 120 Hz display,
device pixel ratio 2, and an 800 × 555 logical-pixel list viewport. All 1,000
fixture topics remain in the normal entity cache. Titles, parent/category
paths, tags, status icons, and activity are local data; no network images are
included. CPU profiling was enabled using the same engine switch as
`flutter run --profile`.

The numbers below are the median of each run's 95th-percentile UI
build/layout/paint time. Frame overruns count either UI or raster exceeding the
8.33 ms display budget. Raw per-run measurements are in
[topic-list-scrolling.json](topic-list-scrolling.json).

| Scenario | Baseline p95 | Fixed p95 | Row builds, baseline → fixed | Over-budget frames across all runs |
| --- | ---: | ---: | ---: | ---: |
| Steady, 180 steps × 40 px | 1.527 ms | 1.059 ms | 100 → 100 | 0/300 → 1/300 |
| Fast, 40 steps × 1,200 px | 15.984 ms | 7.121 ms | 698 → 345 | 97/120 → 2/123 |
| Return, 40 steps × −1,200 px | 12.973 ms | 7.217 ms | 625 → 357 | 80/120 → 0/123 |

The fixed captures include the deferred cache-fill frame after fast scrolling.
Fast-scroll p95 improved by 55%. These are fixture measurements, not a guarantee
for every feed or device.

Reproduce with:

```sh
flutter run --profile -d macos -t tool/topic_list_scroll_profile_main.dart
```

The fixture prints a report and the saved JSON path for each phase. It verifies
that every requested topic remains available before running, so an oversized
fixture cannot accidentally benchmark evicted records and blank rows.

## Verification

- 155 focused tests passed, covering the list, inbox, pagination, restoration,
  keyboard navigation, and diagnostics; static analysis and formatting passed.
- The scrolling regression checks actual visible-row construction and stable
  offsets without timing thresholds. It fails on the baseline (13 row builds
  when at most 7 rows were needed) and passes with the fix. A 20-frame diagnostic
  reproduction went from 236 builds and 2,064 pixels of correction to 120 builds
  and no correction.
- Native visual/accessibility inspection confirmed populated rows, independent
  category/tag links, activity columns, and wheel scrolling. Keyboard and
  restoration coverage comes from the Flutter tests; the profiling fixture does
  not mount the full application shortcut host.
- Native timing claims apply to macOS only. The production component library,
  row appearance, and dependency pins are unchanged.
