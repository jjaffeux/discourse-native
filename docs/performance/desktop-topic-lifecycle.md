# Desktop topic opening and closing

Opening a topic over its source list keeps the list mounted in the existing
workspace. Closing restores that list's state and scroll position and disposes
the reader. Previously, desktop panel readers bypassed the workspace, disposing
the list on opening and constructing it again on closing. Panel headers continue
to own their tabs, so the reader does not add a second tab strip.

The retained list excludes focus and pauses tickers while hidden. Topic rows
listen to ticker availability to cancel hover prefetching without rebuilding
their visual trees. Both the list and rows still react to their other inherited
dependencies. Retention remains bounded by the existing three documents per
desktop panel; each source-backed reader now also retains its lazy source list.

Measuring floating progress controls updates only the trailing scroll-padding
sliver. The measurement previously rebuilt the whole reader, including its
header and post delegate. The padding calculation and anchor correction are
unchanged, including on phones.

## Widget work

`test/desktop_topic_lifecycle_performance_test.dart` drives the production shell
at 1440 by 900 with a 100-topic source list and a separate live reader. It scrolls
the source 20 logical pixels, clicks the first topic, waits for 60 formatted posts
to load and render, and presses the reader's Back to list control. Three cycles
check topic identity, rendered content, source state and position, focus and
ticker exclusion, reader disposal, tab-strip count, and framework exceptions.

Five alternating baseline/candidate runs exercise macOS, Linux and Windows.
Baseline is `f00de6dc2`; Flutter 3.47.7 and Dart 3.13.5 run on macOS. The baseline
comparison uses `--dart-define=EXPECT_RETAINED_LIST=false` to check its expected
list disposal while keeping the content and navigation checks enabled. The
ordinary regression requires retention and one reader build per opening.

| macOS builds per warm action, median (range) | Baseline | Updated |
| --- | ---: | ---: |
| Open, whole shell | 2,276 (2,276–2,276) | 2,572 (2,572–2,572) |
| Open, reader widget | 2 (2–2) | 1 (1–1) |
| Close, whole shell | 2,908 (2,908–2,908) | 1,775 (1,775–1,775) |
| Open plus close, whole shell | 5,184 (5,184–5,184) | 4,347 (4,347–4,347) |
| Source-list mounts on close | 1 (1–1) | 0 (0–0) |

Closing performs 39% fewer widget builds; a warm cycle performs 16% fewer.
Opening performs more total builds because the source remains mounted and its
selection updates, while the reader itself builds once. Linux and Windows show
the same behavior, with totals three builds lower on opening and five lower on
closing. Every run passed its behavioral checks. Raw observations are in
[widget-work.json](data/desktop-topic-lifecycle/widget-work.json).

These are deterministic debug work counts, including mounts across the shell.
They do not measure teardown, native latency, frame time or GPU work.

## Native profile

`integration_test/desktop_topic_lifecycle_performance_test.dart` runs the same
production shell with bundled fonts and local API fixtures in a macOS profile
build. Each process warms one open/close cycle and measures seven further cycles.
Frame timestamps bound each action from the row or close-button tap through
settling. Every opening must render a formatted post and resolve all 60 post IDs;
every close must return to its list without framework exceptions.

The local unsigned build uses a temporary `XCODE_XCCONFIG_FILE` containing
`CODE_SIGNING_ALLOWED = NO`, `CODE_SIGNING_REQUIRED = NO`, `ARCHS = arm64` and
`ONLY_ACTIVE_ARCH = YES`. Repository signing settings are unchanged. Preserved
baseline and candidate bundles are run alternately five times per side.

| UI-thread work, ms, median of run medians (range) | Baseline | Updated |
| --- | ---: | ---: |
| Largest frame during opening | 5.263 (4.195–7.878) | 6.363 (4.923–8.670) |
| Sum of opening frames | 14.332 (10.180–16.510) | 14.816 (11.459–17.042) |
| Largest frame during closing | 9.254 (6.321–11.846) | 4.619 (3.734–5.982) |
| Sum of closing frames | 14.370 (12.223–17.386) | 10.635 (9.714–11.032) |

Closing has 50% lower peak UI-thread frame work and 26% less summed UI-thread
work in this fixture. Opening has no demonstrated frame-time improvement: its
run ranges overlap and its median peak is higher. The reader avoids a redundant
rebuild, but retaining the source also keeps its selection and focus updates
alive. The stronger measured benefit is returning to the list.

The host had concurrent work, with load averages between roughly 5 and 10 on
18 logical processors. Alternating preserved bundles avoids rebuild and cache
differences between samples. Every measured run passed. Raw per-frame durations
and run summaries are in [native-frames.json](data/desktop-topic-lifecycle/native-frames.json).
Raster durations were almost entirely zero or one microsecond, so these results
do not establish GPU cost, presented FPS, or visual smoothness. Summed frame work
also excludes the idle time between frames; it is not tap-to-presentation latency.
Remote network loading and retained-list memory were not benchmarked.

## Verification

The lifecycle regression also resizes a hidden source, changes forum brightness
and text scale, replaces the topic, and checks that the same source returns with
current dependencies and layout. The existing topic, mobile layout/sheet,
tab-switch, row-allocation, sidebar and hover-prefetch tests cover the shared
behavior. A local golden comparison of the open reader and restored list matches
baseline exactly.

```sh
flutter test --no-pub \
  test/desktop_topic_lifecycle_performance_test.dart \
  test/desktop_topic_page_test.dart \
  test/topic_inbox_test.dart \
  test/mobile_topic_layout_test.dart \
  test/mobile_topic_sheet_test.dart \
  test/topic_sidebar_store_test.dart \
  test/tab_switch_performance_test.dart \
  test/topic_list_row_allocations_test.dart \
  test/topic_hover_prefetch_test.dart
```

```sh
flutter drive -d macos --profile \
  --driver=integration_test/performance_driver.dart \
  --target=integration_test/desktop_topic_lifecycle_performance_test.dart
```
