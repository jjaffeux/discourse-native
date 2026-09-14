# Long-post topic scrolling

The [September 14 ordinary-reply follow-up](ordinary-topic-scrolling.md)
addresses repeated construction of smaller rich replies and paging rebuilds
that the original long-post fixture did not cover.

The supplied September 13 debug capture showed UI stalls rather than raster
pressure: 56 of 134 topic-active frames exceeded 8.33 ms, UI p95 was 74.15 ms,
and raster p95 was 2.32 ms. The largest posts repeatedly appeared in layout
samples. Debug assertions and compilation contribute to those timings, so they
are not directly comparable with profile measurements.

The reproducible issue was recycling already-rendered long posts. Leaving the
viewport destroyed their HTML trees; returning parsed, built and laid them out
again. Saving a new fallback height also rebuilt the topic's child delegate.

The topic now retains up to three recently viewed long-post trees, with a total
budget of 262,144 HTML characters. This is a cost proxy, not a measurement of
heap bytes. Ordinary posts, evicted posts, and a single post exceeding the
budget still recycle. Actual post edits continue through the entity store;
retention updates its budget when those edits change the HTML length. Changing
topic/navigation identity clears the cache, and disposal releases its owners.

Both topic header arrangements use the existing `SuperSliverList` inside a
`CustomScrollView`, decorated by the existing Native `DScrollBar`. The sliver
defers offscreen cache construction during fast scrolling and lays out dirty
kept-alive rows. That last setting is required: async HTML and offscreen edits
otherwise leave Flutter's text selection querying unlaid-out paragraphs. The
previous standalone `SuperListView` convenience wrapper did not expose it.

## Native comparison

Two baseline runs at `76080324` and three fixed runs used the same macOS desktop,
Flutter 3.47.2 profile mode, Skia on Metal, 120 Hz, device pixel ratio 2, and a
1280 × 860 logical-pixel topic view. The local fixture has 60 posts, including
14,640- and 82,800-character HTML posts, with no network media. Each pass makes
nine index jumps between posts 1, 20 and 41 and scrolls 30 × 40 pixels after
each jump. The first long post is warm before capture; post 20 is initially
uncached. A second pass repeats the same movement in the same process.

Values below are medians of each version's per-run percentiles. Frame counts aggregate
all runs for that version. Per-run summaries are in [topic-scrolling.json](topic-scrolling.json).

| Measurement | Baseline | Fixed |
| --- | ---: | ---: |
| First-pass UI p99 | 12.17 ms | 6.64 ms |
| Return-pass UI p95 | 2.09 ms | 1.84 ms |
| Return-pass UI p99 | 13.58 ms | 3.24 ms |
| Return-pass UI overruns | 10 / 568 | 2 / 840 |
| Long-post mounts per return pass | 6 | 0 |
| Post layouts per return pass | 42 | 24 |

Return-pass p99 improved by about 76% in this fixture. First construction still
costs work: the fixed first passes had six UI overruns across 840 frames,
with maxima of 13.02, 14.71 and 17.97 ms. The third run verified the final
lifecycle refinements; its return-pass p99 was 8.01 ms, versus 3.12 and 3.24 ms
in the first two runs. Baseline first passes had nine UI overruns.
Some first-pass raster spikes also occurred; this change targets UI work.
Other tasks were active on the desktop, so these small samples are evidence of
the removed work, not a general frame-rate guarantee. They do not reproduce
the private topic's exact HTML or measure iOS/Android scrolling.

Reproduce with:

```sh
flutter run --profile -d macos -t tool/topic_scroll_profile_main.dart
```

The fixture prints both reports and the paths to their JSON captures. The
comparison used isolated ad-hoc-signed bundles with the standard Flutter
`enable-dart-profiling=true` engine switch. After measurement, native wheel
scrolling away and back, visible topic progress, and drag selection with the
copy-quote toolbar were checked in the light-theme fixture. Dark-theme
retention and viewport/navigation behavior are covered by widget tests.

## Verification

Final integration with main at `b3507115` passed all 290 tests across the
scrolling, topic-reading, keyboard, diagnostics and reading-lane suites.
Tests cover reuse, least-recently-viewed
eviction, both cache limits, offscreen edits, deferred keep-alive notification,
disposal, pagination, anchor correction, visible topic context, day separators,
progress and highlights. The reuse regression fails on the original source
because the long HTML element is disposed. Oversized posts retain the previous
fallback-height behavior without repeated delegate refreshes.

Targeted downstream checks also passed: diagnostics toggles at widths 390,
1000 and 2428; pinned-sidebar reading-lane alignment; and independent topic
list/reader keyboard selections. Static analysis passed without issues.

Initial broader runs exposed existing failures on the original baseline. The
separate test-repair change merged into main before final integration; its
repairs were preserved, and all affected suites passed together. Formatting
and full-project static analysis also passed on the final integration source.

## First-render follow-up

[First render of long topic posts](long-post-first-render.md) measures the
remaining conversion and layout costs separately and records the subsequent
staged-mounting change, including its limits and whole-topic comparison.
