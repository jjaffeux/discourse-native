# Category grid intrinsic-layout audit

**Status: native improvement verified; awaiting merge.**

The candidate change is limited to single-column category grids. Each row
previously used `IntrinsicHeight` plus a stretching `Row`, even when it contained
one card. A one-card row now lays out its card directly at the existing width.
Two/three-column rows still use intrinsic measurement to equalize peer heights.
No card content, control, semantics, breakpoint, minimum height, or paging logic
changes. No UI-kit extension is needed.

## Workload and deterministic evidence

Baseline source: `09353ddc`, `lib/src/shell/categories_page.dart`. Flutter 3.47.4
(revision 9584c6713b), Dart 3.13.3; the repository SDK pin is unchanged.

The fixture is a filtered public Meta categories response fetched 2026-09-18:
12 root categories with 33 featured topics, including empty and long-title cards.
The 60-category case repeats those records with unique category IDs; it is an
explicit synthetic expansion. Both use the actual `CategoriesPage` with its
controller, category references, card implementation, theme and sliver list.
Networking and persistence dependencies use existing test fakes.

`category_grid_layout_trace_test.dart` captures Flutter VM timeline layout events
with `debugProfileLayoutsEnabled`, mounting at each width then making 30 jumps
of 180 logical pixels, clamped at the end. Each combination runs four times:
one warmup and three measured repeats. Tests use a 1200×900 viewport, DPR 1,
default Flutter test fonts/platform. Widths 390/700/1100 exercise one/two/three
columns respectively. These are operation counts, not native timing claims.

| Categories | Width | Intrinsic queries before → after | Dry-layout queries before → after | Intrinsic row layouts before → after |
| --- | --- | --- | --- | --- |
| 12 | 390 | 746 → 0 | 116 → 0 | 12 → 0 |
| 12 | 700 | 752 → 752 | 116 → 116 | 6 → 6 |
| 12 | 1100 | 754 → 754 | 116 → 116 | 4 → 4 |
| 60 | 390 | 1690 → 0 | 259 → 0 | 27 → 0 |
| 60 | 700 | 3141 → 3141 | 486 → 486 | 25 → 25 |
| 60 | 1100 | 3770 → 3770 | 580 → 580 | 20 → 20 |

Counts are timeline query events and may include cache hits; they are not counts
of expensive cache-miss computations. Normal paragraph and wrap layout counts
are unchanged. All captured category x positions, widths and heights match the
baseline in every run. Lazy scrolling visits only part of the 60-card dataset at
narrow widths; the workload does not force construction of every card.
Full repeat results are in `category-grid-layout-counts.json`.

## Regression checks

- Geometry snapshots of all 12 real cards at three widths preserve natural
  heights, wrapping and column positions, including the 118-pixel empty card.
- Narrow grids contain no `IntrinsicHeight`; peer rows retain it.
- Existing row equal-height, breakpoint, navigation, paging and lazy rendering
  tests pass. The named keyboard target/44-pixel touch target/Enter activation
  test now explicitly runs at 390 pixels.
- Targeted analyzer is clean.

Commands:

```sh
flutter test --no-pub test/categories_page_test.dart test/category_grid_geometry_test.dart
flutter test --no-pub --enable-vmservice --dart-define=CATEGORY_LAYOUT_TRACE=true test/category_grid_layout_trace_test.dart
flutter analyze --no-pub lib/src/shell/categories_page.dart test/categories_page_test.dart test/category_grid_geometry_test.dart test/category_grid_layout_trace_test.dart test/support/category_grid_fixture.dart tool/category_grid_profile_main.dart
```

For an identical baseline trace, restore only `categories_page.dart` from the
baseline revision, run the trace command, and retain `/tmp/category-trace-*.json`
before restoring the fixed source. No production instrumentation is added.

## Native capture protocol

`tool/category_grid_profile_main.dart` runs the same production page in an
isolated macOS fixture. It embeds the fixture at compile time (base64 avoids
multiline compiler-define parsing). An existing Native `DButton` explicitly starts
the run after activation; a 10-second warmup requires uninterrupted resumed
lifecycle, enabled semantics, and stable viewport metrics. The warmup records a
numeric physical size, DPR and refresh rate baseline without hardcoding the
machine's dimensions. Every sample must retain that baseline, enabled semantics,
and its actual requested page width through the 1100ms timing-delivery drain.
Observers latch any non-resumed transition, viewport metrics notification,
semantics-state change or accessibility-feature change; returning to the original
state cannot make an interrupted sample valid. Explicit post-drain checks verify
semantics, lifecycle, viewport and page size. Baseline/fixed outputs must have
matching numeric viewport/page dimensions and DPR before their timings can be
compared. The harness records start/end card geometry plus every scroll offset.
It performs 60 jumps of 90 logical pixels,
returning to the beginning when the bottom is reached. One warmup and five
measured repeats run for each dataset/width combination.

Frame timings are selected by `FramePhase.vsyncStart` within the exact
`Timeline.now` measurement interval, with a 1100ms delivery drain. Raw frame
arrays permit total UI/raster-work comparison per 60-step workload as well as
per-frame statistics. The 1100-pixel macOS host uses the production reading lane
cap and therefore remains two columns; three-column coverage is provided by the
widget tests. All native numbers measure macOS, including the phone-width host.

An initial collector used callback-time clearing and a 200ms drain. Its results
were discarded after review identified batched-timing contamination. An early
launch also overlapped other builds/tests. Those provisional results are not
included in the retained evidence.

Prepare the embedded fixture without adding app assets or changing entitlements:

```sh
python3 - <<'PY'
import base64, json
with open('/tmp/category-profile-defines.json', 'w') as output:
    json.dump({'CATEGORY_FIXTURE_BASE64': base64.b64encode(
        open('test/fixtures/categories/meta.json', 'rb').read()
    ).decode()}, output)
PY
flutter build macos --profile --no-pub --dart-define-from-file=/tmp/category-profile-defines.json -t tool/category_grid_profile_main.dart
```

Build identical baseline/fixed review copies, with separate bundle identifiers
and ad-hoc permitted debug entitlements following the component-library review
conventions. Shipping entitlements/provisioning remain untouched. Launch only
these isolated executables under the shared desktop/profiling lease, with other
audit builds/tests paused. Results are emitted as `CATEGORY_PROFILE` JSON to
stdout. Do not replace or terminate the normal app.

### Retained native results

Device: Apple M4 Pro, arm64 macOS; Flutter 3.47.4 / Dart 3.13.3, profile mode,
Skia on Metal. Every retained sample used a 1280×860 logical viewport, DPR 2,
reported refresh rate 120Hz, explicit semantics and resumed lifecycle.
LaunchServices opened exact-path isolated V2 bundles; an observed CUA container
click activated the central Native Start button. The 10-second guarded warmup
completed before capture. Both processes exited normally after each launch;
the shared desktop lease was released after each pair.

Four independent process launches provide two comparisons in opposite orders:

- Baseline then fixed: first/last sample starts 10:27:40–10:29:15 UTC and
  10:30:07–10:31:42 UTC on 2026-09-18.
- Fixed then baseline: 10:33:36–10:35:11 UTC and 10:36:13–10:37:48 UTC,
  using the same binaries, workload and guards. Exact per-sample timestamps
  are preserved in the raw archives and summary below.

All 120 measured runs selected exactly 60 build/raster/vsync frame records.
One fixed 60-category/1100px **warmup** in the first pair had 61 frames; it is
excluded, along with every other warmup. Pairwise start/end card positions,
widths and heights, all 60 scroll offsets, scroll extents, viewport dimensions,
page dimensions and DPR match exactly for all 36 runs in each pair.

The table reports mean **total UI work per identical 60-step workload**, not
elapsed wall time. Each cell summarizes five measured repeats. Frame means are
reported separately in the machine-readable summary; the identical 60-frame
measured denominators prevent idle/extra-frame dilution.

| Categories | Width | Baseline→fixed order: UI ms before → after | Fixed→baseline order: UI ms before → after |
| --- | --- | --- | --- |
| 12 | 390 | 73.695 → 66.239 (−10.1%) | 54.863 → 46.897 (−14.5%) |
| 12 | 700 | 87.418 → 85.470 | 63.883 → 62.305 |
| 12 | 1100 | 92.425 → 89.990 | 65.361 → 66.787 |
| 60 | 390 | 72.720 → 58.599 (−19.4%) | 50.175 → 46.695 (−6.9%) |
| 60 | 700 | 91.322 → 93.294 | 66.883 → 64.391 |
| 60 | 1100 | 88.586 → 92.189 | 67.981 → 67.395 |

For the 390px target, mean UI work **per frame** was 1228.2→1104.0µs (12
categories) and 1212.0→976.7µs (60) in the forward pair; 914.4→781.6µs and
836.3→778.3µs respectively in the reverse pair.

Absolute timings fell across the entire second pair, including the unchanged
multi-column controls. This machine-wide variance prevents treating the pooled
samples as one precise speedup. The narrower claim is supported: single-column
UI work decreases in both process orders and both data sizes, consistent with
eliminated intrinsic passes. Control differences change direction and remain
smaller than the target reductions in their corresponding pair.

Raster results are mixed. At 390px the forward pair's mean total raster work was
77.317→83.863ms (12) and 89.823→86.017ms (60); the reverse pair was
53.411→53.076ms and 58.134→59.154ms. No raster improvement, FPS improvement,
or smoother-native-frame claim is made. No iPhone was profiled.

Per-run distributions, totals, frame means, and parity checks:
[category-grid-native-summary.json](category-grid-native-summary.json).
Complete raw arrays and geometry, including excluded warmups, are stored as
lossless gzip JSON:

- [Forward baseline](category-grid-native-baseline.json.gz)
- [Forward fixed](category-grid-native-fixed.json.gz)
- [Reverse baseline](category-grid-native-baseline-reverse.json.gz)
- [Reverse fixed](category-grid-native-fixed-reverse.json.gz)

Read an archive using `json.load(gzip.open(path, 'rt'))` in Python. No VM-service
URLs or authentication tokens from launch logs are included.

### Excluded earlier attempts

The earlier callback-time collector and its provisional results remain excluded.
At 00:33 UTC the first timestamp-corrected attempt rejected startup because the
app lifecycle was not resumed (`null`); the computer-use tool reported a locked
Mac. That fixture was stopped and its lease released. Later guard revisions
added sticky lifecycle/metrics/semantics validation and explicit activation.
Only the V2 guarded captures described above support native acceptance.
