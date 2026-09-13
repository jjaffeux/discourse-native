# First render of long topic posts

The long-post cache in `843c8968` avoids rebuilding recently viewed posts. It
cannot reduce the first uncached render. This follow-up (`26b1fb2b`) spreads
initial mounting and layout over frames while keeping the existing post,
selection, quote, and scroll ownership.

## Findings and chosen implementation

The installed HTML renderer moves parsing into an isolate, but converts the DOM
into widget descriptions synchronously on the UI isolate. It then mounts and
lays out the entire post as a column. These are separate costs: the conversion
can block between frames and therefore does **not** appear in Flutter's frame
build duration.

A standalone experiment with 450 paragraphs compared the production
`CookedHtml` renderer in column, sliver, and progressive modes. Medians across
four cycles, in milliseconds:

| Measurement | Column | Sliver prototype | Progressive |
| --- | ---: | ---: | ---: |
| HTML-to-widget conversion | 20.75 | 23.32 | 21.13 |
| Largest cold UI frame | 29.48 | 3.38 | 3.94 |
| Largest layout-phase sample | 24.93 | 1.70 | 2.29 |
| First text observed | 73.51 | 45.02 | 47.88 |
| Completed column ready | 73.51 | — | 157.22 |

The sliver prototype initially mounted about 18 paragraphs. Adopting it directly
would require changing the topic's box-based post rows and their per-post
selection owners. It also leaves synchronous HTML conversion intact.

The shipped step instead mounts an initial batch of 64 top-level widgets
(usually 32 paragraphs plus margins). A shared queue mounts one additional
batch per frame, so retained posts cannot each schedule another batch in the
same frame. Bodies with at most 128 widgets use their original column directly.
The rest of the body is estimated from the measured prefix until it completes;
existing paragraphs keep their final offsets as content is appended below.

This does not split or reserialize HTML. CSS containers remain intact: the
factory stages only an already-normalized root column, because the HTML
library's non-column modes can otherwise unwrap CSS blocks. Completed edits
and palette changes retain their existing whole-body update behavior.

The post's completion signal prevents a temporary estimate from becoming a
saved minimum height if it is recycled early. An existing saved height is also
kept until mounting finishes. Disposing the post cancels its queued work.
The previous three-post / 262,144-HTML-character retention budget still applies.

## Production topic comparison

Two baseline/progressive process pairs used the same 60-post topic fixture,
Flutter 3.47.2, macOS profile mode, Skia on Metal, a 120 Hz display, DPR 2, and a
1280 × 860 logical viewport. Post 1 was warm before capture; post 20 contained
450 paragraphs / 82,800 HTML characters and was initially uncached.

For the frames laying out post 20 after its loading placeholder:

| Measurement | Baseline runs | Progressive runs |
| --- | --- | --- |
| Largest UI frame | 13.49 / 11.32 ms | 2.89 / 3.40 ms |
| Largest post-layout sample | 5.89 / 6.25 ms | 0.95 / 0.88 ms |

The median of those peak UI samples fell about **75%**. Subsequent batches
completed over roughly another 120 ms. This trades later full-body completion
and additional total setup work for smaller bursts and earlier readable text.

Whole-topic results were mixed and variable. First-pass UI p99 was 5.90 / 10.82
ms for the baseline and 9.98 / 13.53 ms for progressive mounting. Return-pass
p99 was 6.55 / 9.80 ms and 9.89 / 10.07 ms respectively. Other tasks were active
on the machine; these small samples do not demonstrate an overall topic p99
improvement. The per-post measurements identify the specific work reduced.
All run summaries are retained in [the measurements](long-post-first-render.json).

## Remaining limits

HTML-to-widget conversion still blocks the UI for about 20 ms in the renderer
fixture, outside the reported frame build timings. This change does not make
huge posts stall-free. Removing that pause requires incremental conversion or
a different HTML construction pipeline; changing render mode alone is insufficient.

A single enormous code block, table, or nested CSS container still uses its
existing renderer. All blocks in a staged column eventually mount, so this is
not full viewport virtualization. Fast navigation can briefly reach an unfinished
tail. No iOS/Android device measurements or private-topic HTML were used.

## Reproduction and verification

```sh
flutter run --profile -d macos -t tool/long_post_render_profile_main.dart
flutter run --profile -d macos -t tool/topic_scroll_profile_main.dart
```

The topic harness now obtains the `Scrollable` enclosing its `SuperSliverList`,
rather than taking the first scroller (which can be the topic header). Both
comparison sources used this corrected harness. Direct ad-hoc bundle launches
used Flutter's standard `FLUTTER_ENGINE_SWITCHES=1` and
`FLUTTER_ENGINE_SWITCH_1=enable-dart-profiling=true` environment variables;
passing that switch as a macOS executable argument does not enable the profiler.
Only temporary review bundles had their signing entitlements adjusted.

412 focused tests passed, and static analysis was clean. Coverage includes
prefix reuse and final geometry, CSS width preservation, edits during and after
mounting, palette changes, selection across batches, full formatted copy-quote,
disposal, variable-height jumps in both topic layouts, early oversized-post
recycling, the existing retention/viewport/pagination tests, downstream cooked
markup, and reading/keyboard integration.

Native verification covered the light topic fixture at 1280 × 860: automated
jumps, manual wheel scrolling away and back, matching topic progress, and drag
selection with the copy-quote toolbar. Dark palette behavior was exercised in
widget tests; it was not a separate native device measurement.

Final integration with main `9de54a39` passed the same 412 tests with randomized
seed `391613`, formatting checks, and full-project static analysis. Two stale
notification assertions were updated for main's combined notification button;
they continue to verify the displayed count and live count updates.
