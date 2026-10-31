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
