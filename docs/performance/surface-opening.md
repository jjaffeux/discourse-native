# Topic and composer opening — September 16

Opening now preserves the reader's panel ancestry, avoids rebuilding the
composer for unrelated shell notifications, and mounts a new sheet reader only
at its final location. The hidden source list retains its last visible geometry
instead of reflowing underneath a newly opened composer. Theme, text scaling,
direction and source changes invalidate that retained presentation. The reader
has its own repaint boundary. The topic navigator also owns a semantic
boundary, keeping its route semantics inside the workspace when editor
selection overlays appear. This fixes missing surrounding navigation and the
macOS accessibility-tree update errors reproduced on the original build.

The topic initially lays out visible replies with no offscreen cache, then
restores Flutter's normal cache on the next frame. This spreads initial work
across frames without reducing the steady-state scrolling cache. Navigation
identity and disposal guard the deferred update.

## Instrumentation

`SurfaceOpeningTrace` emits content-free request, response, publication, build,
editor mount, editor focus and completed-frame milestones. It is inactive by
default. Enable timeline markers in a normal app run with:

```sh
flutter run --profile -d macos --dart-define=TRACE_SURFACE_OPENING=true
```

Look for `opening.topic.*` and `opening.composer.*` in the DevTools timeline.
`contentFrame` and `visibleFrame` mean completion of Flutter layout/paint, not
on-screen presentation by the GPU. Topic network and category-loading stages
remain distinguishable from rendering. These markers contain no URLs, topic
identifiers, post text or draft content.

The standalone harness mounts the production `AdaptiveShell`, topic reader,
Native sheet and composer. It records actual engine `FrameTiming` values,
filters them by vsync timestamps and waits for batched delivery before export.
After startup it keeps semantics enabled throughout each capture, rejects
captures with no rendered frames and verifies editor focus. Optional
CPU summaries are collected after each measurement window, using the existing
CPU profiler helper; an unavailable profiler is reported explicitly.

```sh
OPENING_SHEET=true OPENING_LABEL=sheet \
  flutter run --profile -d macos -t tool/surface_opening_profile_main.dart

OPENING_SHEET=false OPENING_LABEL=docked \
  flutter run --profile -d macos -t tool/surface_opening_profile_main.dart
```

Keep the window visible. The fixture waits 15 seconds before starting by
default. For controlled native captures, set `OPENING_MANUAL_START=true`,
activate/inspect the window, then create the signal file printed by the
harness. The reported runs use this gate, with no UI inspection during timing.
The fixture uses
30 local topics, 20 rich replies per topic, a fixed 70 ms API delay, no network
media, fake credentials and in-memory drafts. Preferences use an isolated
prefix. Each process opens five previously unvisited topics and reply editors by default,
reopens a cached topic, then opens two new-topic composers. It prints the JSON
path in its sandbox temporary directory. `OPENING_PLACEMENT=bottom` or `left`
selects another composer placement; `OPENING_PASSES` changes the topic count
(default five, at most 30). `OPENING_CPU=true` requests CPU summaries. The Flutter
launcher enables CPU sampling; direct executable launches must request the same
engine profiling switch to obtain samples. `--dart-define=OPENING_DARK=true`
selects the dark palette.

## Native measurements

The comparison uses macOS arm64 profile builds, Flutter 3.47.4 / Dart 3.13.3,
Skia on Metal, a 120 Hz display, DPR 2 and a 1280 × 860 logical viewport. The
repository's Flutter 3.47.2 pin and lockfiles were not changed. Isolated ad-hoc
fixture bundles omit the restricted push entitlement and retain the app sandbox.
Baseline production source is `a217dda2` with the same opening markers added.
CPU sampling is disabled in the comparison runs; separate diagnostic runs used
it. Neither builds nor tests ran during the reported captures.

The matched reports use eight passes per process: one baseline/final pair for
sheets and two pairs for docked presentation. The table pools passes 1–7 across
both docked pairs and reports the median of each opening's worst UI frame.
Pass 0 is retained separately. Samples are small and subject to system
scheduling, so these are observations rather than a frame-rate guarantee. UI
time includes build, layout, paint and semantics; GPU time is reported
separately. Raw events, every frame, cold passes and outliers are retained in
[surface-opening.json](surface-opening.json).

| Surface | Baseline median peak UI | Final median peak UI |
| --- | --- | --- |
| Sheet topic | 7.09 ms | 7.00 ms |
| Sheet composer | 7.76 ms | 6.77 ms |
| Docked topic | 8.70 ms | 8.93 ms |
| Docked composer | 12.18 ms | 7.82 ms |

Composer median peak UI time fell about 13% in sheets and 36% when docked.
Topic medians are essentially unchanged: the docked difference is +0.23 ms.
Worst warm topic UI frames fell from 9.84 to 8.41 ms in sheets and from 14.39
to 11.84 ms when docked. The first docked comparison had a slower final median;
the matched repeat did not reproduce that increase. Both pairs are included,
not just the faster result. The regression tests establish the removed
rebuild/layout work independently of timing variance.

Across the three final captures, all 940 measured UI and raster durations were
below 16.67 ms. Peak UI time was 14.61 ms; peak raster time was 11.00 ms.
There were 28 UI and six raster durations above the 8.33 ms budget of the
120 Hz display. Sheet composer raster misses increased in this sample (zero
to five warm misses), so this does **not** establish consistently smooth
120 Hz opening. All three final native runs completed without accessibility
bridge errors.

An initial ungated first-use baseline probe included a 331 ms raster spike.
Its raw frames are retained as `initialColdProbe`, outside the matched
comparison. Shader-cache cold starts were not controlled, and this work does
not establish removal of first-use shader stalls.

## Verification

367 focused tests passed, including draft restore/close/failure handling,
composer focus and docking, sheet dismissal and presentation changes, source
list retention, topic lifecycle, progressive HTML and scroll churn. Full-project
`dart analyze` passed. Touched Dart code was checked using the project's Dart
3.12 formatting rules.

Five new regressions fail on the original `a217dda2` production tree and pass
with this change: no initial reader mount outside the sheet, no cooked-post
rebuilds on composer opening in either presentation, no editor rebuilds for
reader-position reports, and no hidden-list reflow during composer opening.
A sixth regression verifies that surrounding navigation remains accessible
before and after opening a sheet and editor; it also fails on the original
source. Two further tests verify that visible replies precede cache expansion
without moving the reading position. Three trace tests cover disabled recording, owner
retirement and callbacks from an earlier capture.

The existing `topic_view_lifecycle_test.dart` test named “keyboard navigation
scrolls and jumps through the topic” fails unchanged on an isolated checkout of
`a217dda2`: expected an offset above 2684.5, got 2598.5. It was excluded from the
367 passing cases and was not modified.

Native interaction checks covered opening/closing topics and reply/new-topic
composers, typing into a sheet composer, preserving that draft when switching
the reader to docked presentation, and bottom docking. These used local fixture
data. Widget tests cover additional mobile platform variants, RTL, large text,
resizing, focus, selection, undo history and background drafts; they are not
physical iOS/Android measurements. The native performance comparison uses the
light palette and right-docked composer. Cold media, enormous nested HTML,
server latency and other machines are outside this fixture's timing claim.
