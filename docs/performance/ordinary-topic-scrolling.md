# Ordinary rich topic scrolling — September 14

The [prepend follow-up](topic-prepend-scrolling.md) fixes temporary offscreen
reply construction and active-drag displacement when earlier pages arrive.

The new user capture exposed a gap in the earlier long-post work: 81 of 397
frames exceeded the 8.33 ms UI budget, with a 108.40 ms maximum. No raster
frame exceeded that budget. Most expensive posts contained only 1–5 KB of
HTML, below the long-post retention threshold. The capture contained 115 row
mounts, 114 disposals and 12 topic builds in 11.7 seconds, including five
appended pages. Native wheel scrolling through the same open topic reproduced
slow frames in its debug build.

The original profile fixture concentrated on two enormous paragraph-only
posts. It did not exercise ordinary rich replies being repeatedly recycled.

## Change

The existing sliver now retains up to 24 recent reply trees, including ordinary
replies. The total HTML budget remains 262,144 characters, and at most three
large replies can be retained. These are bounds on retained trees and an HTML
cost proxy, not measured heap bytes. Least-recently-viewed eviction, account
and navigation resets, and post disposal still release ownership.

Paging replaces the sliver delegate so it can expose new replies. Previously
that also rebuilt existing reply contents, including actions, selection owners
and HTML widgets. Each stored reply now preserves its content widget while
its inputs are unchanged. Post entity subscriptions, topic changes, theme,
plugin dependencies, keyboard selection and highlights continue to update it.

## Native comparison

The new `SCROLL_MIXED` fixture uses the production reader with 114 synthetic
replies containing quotes, inline formatting, links, code and lists. It starts
with 20 loaded replies and fetches another page while scrolling. Each pass
makes four alternating 120 × 80 pixel wheel-scroll legs, crossing about 19
replies. It has no network media or private post content.

Two baseline/fixed process pairs used Flutter 3.47.2, macOS profile mode, Skia
on Metal, a 120 Hz display, DPR 2 and a 1280 × 860 logical viewport. Baseline
production source is `9273026f`. The numbers below are the two return passes,
after each process's first pass:

| Measurement | Baseline runs | Fixed runs |
| --- | --- | --- |
| UI p95 | 5.03 / 5.13 ms | 1.52 / 1.62 ms |
| UI p99 | 7.55 / 6.77 ms | 2.09 / 2.34 ms |
| Maximum UI frame | 10.98 / 9.44 ms | 2.73 / 3.36 ms |
| UI overruns | 3 / 3 of 504 frames | 0 / 0 of 504 frames |
| Raster overruns | 0 / 0 | 0 / 0 |
| Reply mounts | 66 / 66 | 0 / 0 |
| Reply layouts | 82 / 82 | 0 / 0 |

The median of per-run UI p99 fell about 69%. Viewport bookkeeping increased
slightly with retention: p95 was 84–92 µs before and 127–188 µs after. It
remained a small fraction of the frame budget.

The first comparison's first-pass UI p99 fell from 8.28 to 4.97 ms, with UI
overruns falling from five to zero. First-use raster stalls remained in both
versions, reaching 218 / 236 ms; this change does not resolve those stalls.
The second fixed first pass had one 13.06 ms UI frame. The second baseline
first pass was interrupted by window visibility and is excluded from the
first-pass comparison. All summaries, including these limits, are retained in
[ordinary-topic-scrolling.json](ordinary-topic-scrolling.json).

These profile measurements cannot be directly compared with the user's debug
capture. Debug assertions and compilation still add cost. Cold content, media,
enormous nested HTML and movement beyond the retention budget can still cause
work. This is evidence that repeated construction was removed, not a universal
frame-rate guarantee or an iOS/Android measurement.

Reproduce with a visible window:

```sh
flutter run --profile -d macos -t tool/topic_scroll_profile_main.dart \
  --dart-define=SCROLL_MIXED=true --dart-define=SCROLL_LABEL=mixed
```

The harness prints the two report paths. Omit `SCROLL_MIXED` to run the existing
long-post fixture. The comparison used isolated, ad-hoc-signed fixture bundles.

## Verification

Three new widget regressions fail on the original source and pass on the fix:
ordinary reply reuse in both topic layouts, and preservation of already
rendered subtrees while paging starts and completes. They also verify
offscreen edits, disposal, topic archival and theme changes. Rebuild detection
tracks existing element identities; Flutter's `builtOnce` debug flag is only
set when rebuild logging is enabled and cannot establish this assertion alone.
Retention tests cover both row limits, total HTML, LRU order, edits that cross
size classes and frame-safe eviction.

The broader focused run passed 362 tests covering viewport coordination,
reading/anchor behavior, pagination, progress, day separators, highlights,
long-post rendering, selection, keyboard navigation and selected-post refresh.
One existing menu-cursor assertion in `topic_reading_integration_test.dart`
fails on both the original source and this change: it expects a click cursor
where the current menu exposes the basic cursor. It was left unchanged.

Native inspection covered the light-theme reader, wheel scrolling away and
back, matching topic progress, and selecting returned text with the Copy quote
toolbar. Dark theme and live invalidation were checked in widget tests.

Integration with main at `2780e6d6` passed the same 362 selected tests, excluding
the independently reproduced menu-cursor failure, and full-project analysis.
A fresh native profile build of that integration (`9058a837`) retained the
improvement: return-pass UI p99 was 2.27 ms, with no reply remounts and no UI or
raster overruns across 504 frames. First-pass UI p99 was 4.91 ms; the existing
first-use raster spikes remained.

The final candidate based on main `b34e2c86` passed those 362 selected tests,
formatting and full-project static analysis again. Its reply-rendering and
retention code is unchanged from the native integration measurement.

Restart an already-running debug app when applying this change. The stored
reply widget changes from stateless to stateful, which requires a restart
instead of relying on hot reload to preserve the old widget type.
