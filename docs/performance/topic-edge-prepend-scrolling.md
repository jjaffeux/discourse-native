# Earlier-page arrivals at the viewport edge — September 14

The new 15.1-second debug capture contained 102 slow UI frames out of 1,183
at 120 Hz. All five worst UI frames coincided with earlier-page insertion,
taking 90–109 ms. The existing prepend fix was already present. Its benchmark
loaded a page while settled among retained replies and did not cover the
loading header being visible when a page arrives.

## Cause and fix

The earlier-page header remains at index zero while existing replies move
forward. `SuperSliverList` fills index gaps between attached children before
removing children outside the cache area. The header therefore makes it build
reply trees that it immediately discards, and layout through that gap can
move the previously visible reply out of view.

The topic's existing sliver adapter now checks for this gap after a delegate
rebuild. It removes the preceding children only when their measured bounds
are completely before the cache area. Layout then starts from the shifted
reply offsets. Retained replies continue through the normal keep-alive cache.
Normal scrolling without a delegate rebuild or an index gap does not take
this path.

## Native profile comparison

Implementation: `a764630a`; baseline: `c85557a6`.
Two alternating baseline/fixed process pairs used Flutter 3.47.2, macOS profile
mode, Skia on Metal, a 120 Hz display, DPR 2, and a 1280 × 860 logical viewport.
No builds or test runs were active during these comparisons.

`SCROLL_EDGE` starts with replies 95–114 of the existing synthetic rich topic,
with reply 105 selected. It continuously drags upward by 80 pixels per frame.
Each page response takes 150 ms, so five earlier pages arrive during the drag.
The pass ends at the first reply. Quotes, code, lists and links use the
production renderer; the fixture has no account data or network media.

| Measurement | Baseline runs | Fixed runs |
| --- | ---: | ---: |
| Slowest prepend UI frame | 18.05 / 21.52 ms | 3.76 / 3.30 ms |
| Replies mounted and discarded in prepend frames | 28 / 28 | 0 / 0 |
| UI overruns in topic-active frames | 5 / 5 | 0 / 0 |
| Whole-pass UI p99 | 13.68 / 13.88 ms | 3.17 / 2.84 ms |
| Topic-active frames | 399 / 399 | 837 / 837 |

The maximum prepend-frame cost fell 79–85%. Both versions reached the first
reply, but the baseline displaced the viewport across inserted replies and
finished sooner. Whole-pass distributions therefore cover different amounts
of visible content. The prepend-frame timings and temporary mounts are the
direct comparisons. Per-run summaries and every prepend frame are preserved
in [topic-edge-prepend-scrolling.json](topic-edge-prepend-scrolling.json).

One raster overrun occurred in the first pair: 9.00 ms on baseline and 31.02 ms
on fixed. The second pair had none. This change does not address intermittent
raster stalls. These measurements apply to this local macOS fixture, not the
private topic, cold network media, or mobile frame rates. Debug timings cannot
be compared directly with profile timings.

Reproduce with:

```sh
flutter run --profile -d macos -t tool/topic_scroll_profile_main.dart \
  --dart-define=SCROLL_EDGE=true --dart-define=SCROLL_LABEL=edge
```

## Verification

All eight new regressions fail on baseline and pass with the fix. They cover
both topic layouts under Android and macOS physics, including a macOS pull
past the start, preservation of visible and retained replies, and continued
dragging after the page arrives.

The broader run passed 321 tests covering lifecycle, layout, viewport
coordination, retention, paging, highlights, long HTML, selection, reading
progress, topic-list scrolling and selected-post refresh. The existing
`keeps action hover affordances inside the viewport` test failed its click
cursor expectation on both baseline and fixed. Full-project static analysis
and formatting passed.

Native inspection verified reaching the first reply, scrolling away and back,
matching topic progress, and selecting returned text with the Copy quote
control.
