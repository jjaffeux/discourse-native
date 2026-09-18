# Category grid intrinsic-layout audit

**Status: pending native verification; not merged.**

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

### Native result limitation

No native timing claim is retained. At 2026-09-18 00:33 UTC, the corrected
collector rejected startup because the app lifecycle was not resumed (`null`).
The native computer-use tool then reported that the Mac was locked and automatic
unlock was unavailable. The isolated fixture was stopped and the desktop lease
released. An unlocked desktop is required to complete the corrected capture.
Earlier callback-based measurements remain excluded regardless of their apparent
improvement. Deterministic removal of redundant layout queries with unchanged behavior
supports the candidate, but acceptance remains pending native profiling. It does
not establish smoother native frames or a measured native CPU-time reduction.
