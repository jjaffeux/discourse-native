# Desktop topic scrollbar investigation

The reader now preserves an ordinary reply's measured height while its HTML reloads during downward scrolling. The regression reproduced a 454-point reply shrinking to 202 points before its body returned. The repaired case preserves 454 points and keeps the visible reading anchor stationary. Upward scrolling already used this behavior.

This is a layout correction. The native timing comparison does not establish a speedup or resolve every reported slowdown.

## Native evidence

The profile drives the actual Native scrollbar thumb with mouse input through 200 loaded mixed-height replies. Every thirteenth reply contains 60 extra paragraphs. Four 1.5-second sweeps cover cold downward scrolling and repeated reversals. The fixture checks substantial visible-post movement, no page requests, no Flutter exceptions, and actual GPU raster work. The viewport uses the native window size and density.

Five alternating runs per side completed all workload assertions. The primary warm downward frame-build p95 had a baseline median of 2.587 ms, range 2.341 to 3.056 ms. The candidate median was 2.773 ms, range 2.460 to 3.161 ms. The ranges overlap. Each warm downward sweep produced 182 or 183 input updates on the baseline and 182 on the candidate. Both versions reached post 91.

The upward phase also exceeded the predeclared 5% tolerance for scroll-distance variation. The runner rejects the overall comparison as inconclusive. Its tolerance remains unchanged. A separate CPU-sampled diagnostic places reply mounting and layout on the UI work path. Sampling was disabled in timing builds.

The [comparison data](data/topic-scrollbar-dragging.json) preserves all ten run reports, framework hashes, and the inconclusive verdict. Local process logs are in `/private/tmp/discourse-topic-scrollbar/comparison/`. The CPU diagnostic is `/private/tmp/discourse-topic-scrollbar/native-baseline-cpu.json`. Initial traces with a fake viewport produced no GPU work and were discarded. The native launch screen is dismissed before measurement. `--no-dds` prevents the profiler connection from being replaced during startup.

## Reproduce

Build each source revision with the same harness, then copy the complete app bundle before building the other revision:

```sh
flutter build macos --profile --no-pub \
  --target integration_test/topic_scrollbar_performance_test.dart \
  --dart-define=PROFILE_CPU=false
```

The local build used a temporary `XCODE_XCCONFIG_FILE` with `CODE_SIGNING_ALLOWED = NO`, `ARCHS = arm64`, and `ONLY_ACTIVE_ARCH = YES`. Repository signing settings were unchanged.

Compare the copied bundles:

```sh
python3 tool/benchmark_topic_scrollbar.py \
  --baseline /private/tmp/discourse-topic-scrollbar/baseline.app \
  --candidate /private/tmp/discourse-topic-scrollbar/candidate.app \
  --output /private/tmp/discourse-topic-scrollbar/comparison
```

Capture a separate CPU diagnostic:

```sh
flutter drive --profile --no-pub --no-start-paused --no-dds -d macos \
  --driver integration_test/performance_driver.dart \
  --target integration_test/topic_scrollbar_performance_test.dart \
  --dart-define=PROFILE_CPU=true
```

The driver writes folded CPU stacks and frame timings to `build/integration_response_data.json`.

## Validation and limits

All 12 progressive HTML tests and 30 related churn, geometry, and scroll-controller tests passed. Targeted Dart analysis passed. No full suite was run.

The rejected cold-row fallback reserved the list's initial 199-point estimate. A real mouse test passed on the baseline because its pending rows were already 202 points tall. That fallback and its ineffective test were removed.

The retained fix uses the existing measured-height staging record and completion path. It adds no UI-kit API, cache budget, delay, or production test hook. It does not change pagination or map the scrollbar to the entire topic. The user reports the slowdown across all topics. Investigation of per-input handling and shared scrolling behavior continues.

## Header retraction moved the drag track

The follow-up found a pointer-tracking defect in the shared Native scrollbar. A fixed 40,000-point scroll surface reproduces it without HTML, paging, or estimated row heights. With an 80-point retracting header, the grabbed thumb point ends 78 points above the mouse. A 160-point header produces a 157-point error. The zero-height-header control passes.

Flutter records the initial pointer and track-relative thumb offset. The Native page changes the scrollbar's top padding while its header retracts. Flutter converts subsequent pointer displacement using the current track length, while painting adds the current top padding. The changing origin therefore separates the grabbed point from the pointer. Dragging to the viewport's bottom can stop short of the content's end.

The Native scrollbar now adapts the coordinates passed to Flutter by the change in top padding. It waits for painted track geometry when necessary and reconciles a stationary pointer while the header settles. Flutter retains ownership of gesture recognition, scrolling, clamping, and release. A private drag record binds deferred updates to the accepted pointer and scroll position. Release, cancellation, controller replacement, and disposal invalidate pending work.

The correction applies to ordinary downward-axis vertical page scrollbars, including upward mouse movement within those pages. Reversed-axis and horizontal scrollbars retain their existing behavior. No public component option or hit area changes.

The new behavioral cases pass in the Flutter test runner and natively on macOS in profile mode. They assert a maximum 2-point grip error, reaching the content end while the pointer stays inside the viewport, stationary-pointer settling, header expansion during reversal, non-minimum thumb lengths, RTL, final release input, cancellation, controller replacement, disposal, and rejected-pointer ownership. The rejected-pointer case also reproduced a 148.5-point error before its ownership repair.

Run the focused scrollbar cases:

```sh
flutter test --no-pub test/scrollbar_header_drag_test.dart test/d_scroll_area_test.dart
```

Run the same grip cases on the native macOS engine:

```sh
flutter drive --profile --no-pub --no-start-paused --no-dds -d macos \
  --driver integration_test/performance_driver.dart \
  --target integration_test/scrollbar_header_drag_test.dart
```

Local native verification is saved in `/private/tmp/discourse-topic-scrollbar/native-grip-final.log`. Source hashes recorded before that run match the files after the run. This is a verified tracking correction, not a frame-rate speedup claim; the earlier timing comparison remains inconclusive.
