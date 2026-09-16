# Compact topic-list scrolling with events and assignments

The compact list was already lazy: existing topic titles did not rebuild during
scrolling, and the list kept the requested scroll offset. Native CPU samples
instead showed widget mounting, paragraph/layout work, and repeated event-date
formatting as new rows entered the viewport. Scroll bookkeeping stayed small.

Each compact row used a full DTable with a horizontal scrollable even though its
fixed/flex columns fit, and separate hover/animation owners for every cell.
DTable now omits that unnecessary scrollable when its column policies prove
that it fits, and shares one hover background across a single flex row. Real
overflow, intrinsic columns, spanning cells and explicit scroll controllers
retain the existing scrolling path. Row backgrounds remain confined to the
row even when the table receives extra vertical space.

Event schedules now format their identical tooltip/accessibility description
once per schedule and reuse date/time formatters for both endpoints. This cache
belongs to the current schedule; changes to the event, locale or reader
timezone still produce a fresh schedule.

The profile fixture now defaults to compact rows, with events on two thirds of
its 1,000 topics and assignments on half. Some assignments include a post as
well as the topic. All records remain in the normal entity cache; titles,
categories, tags and avatar fallbacks are local. The tool selects the vertical
list explicitly, since baseline tables also contain horizontal scrollables.
The production scroll recorder includes the list display mode in its context.

## Native comparison

Three alternating baseline/fixed process pairs used macOS arm64, Flutter
3.47.4 / Dart 3.13.3, profile mode, Skia/Metal, a 120 Hz display (8.33 ms
budget), DPR 2 and an 800 × 559 logical-pixel list viewport. The baseline is
`8d31b4dd`, including the newly merged category layout, with the same fixture
and display-mode instrumentation. Builds and tests were stopped during captures.

Entries are the median of each run's p50/p95 UI build/layout/paint durations.
Over-budget counts include either UI or raster exceeding the frame budget.
Per-run summaries are in [compact-topic-list-scrolling.json](compact-topic-list-scrolling.json).

| Scenario | UI p50, baseline → fixed | UI p95, baseline → fixed | Over-budget frames |
| --- | ---: | ---: | ---: |
| Steady (180 × 40 px) | 1.376 → 1.258 ms | 2.771 → 2.627 ms | 0/225 → 0/225 |
| Fast (40 × 1,200 px) | 7.230 → 6.480 ms | 9.199 → 9.131 ms | 22/123 → 16/123 |
| Return (40 × −1,200 px) | 7.140 → 6.508 ms | 9.455 → 8.717 ms | 21/123 → 21/123 |

Typical fast/return UI frames improved by 10%/9%. Fast-scroll p95 was essentially
unchanged; return p95 improved by 8%. There are still over-budget frames on this
120 Hz display. All runs built exactly 75 steady, 280 fast and 283 return rows,
so the improvement comes from cheaper rows, not reducing rendered content.
The captures include the deferred cache-fill frame. The isolated experiment
removing only horizontal scrollables did not show a clear timing improvement;
the retained change also consolidates hover owners and avoids duplicate date
formatting. These are fixture measurements, not a guarantee for every feed.


## Reproduction

```sh
flutter run --profile -d macos -t tool/topic_list_scroll_profile_main.dart \
  --dart-define=PROFILE_LABEL=local
```

The tool prints and saves JSON for each phase in the app's temporary directory.
Use `LIST_MODE=card`, `LIST_EVENTS=false`, `LIST_ASSIGNMENTS=false`, or
`SCROLL_WIDTH=390` as additional `--dart-define` arguments to isolate content or
layout. For direct executable launches, CPU samples require Flutter's usual
`FLUTTER_ENGINE_SWITCHES=1` and
`FLUTTER_ENGINE_SWITCH_1=enable-dart-profiling=true` environment variables.

## Verification

- Scroll regression covers cards and compact rows without plugins, with events,
  with assignments, and with both. It checks actual rendered metadata, bounded
  row construction, no title/list rebuilds and unchanged requested offsets;
  it uses no elapsed-time thresholds.
- The two new DTable performance regressions fail on the original component
  and pass with the fix. Coverage also checks overflow after narrowing,
  restoring a fitting viewport, attached caller-owned scroll controllers,
  hover continuity between cells and background bounds.
- 136 focused tests passed, including event schedule dialogs, live timezone
  updates, all-day/multi-day dates, narrow/large-text/RTL layouts, assignment
  visibility/disclosure, table/item behavior, lifecycle and diagnostics. After
  the final background-bounds correction, all 56 affected table/compact/scroll
  tests passed. Static analysis, formatting and the macOS profile build passed.
- A broader downstream run passed 218 tests and failed the existing
  `feed select retains keyboard focus across routes (stacked: true)` test.
  Running that test alone with the original DTable reproduced the same
  `topWeekly` versus `popular` failure; this change does not modify that control.
- Native macOS inspection confirmed populated compact rows, readable event and
  assignment metadata, category/tag links, the assignment disclosure control,
  shared row hover bounds, and wheel scrolling. Opening and closing the event
  schedule displayed the correct start/end times and Europe/Paris timezone.
  Assignment navigation and keyboard behavior were verified in widget tests.

Timing results apply to the local macOS fixture with cached records and avatar
fallbacks. Network/image loading and other device platforms were not measured.
