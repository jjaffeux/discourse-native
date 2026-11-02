# Button surface transform removal

Fast-downward frame-build p95 improves in five alternating native runs per
version. The median falls from 6.316 ms to 5.300 ms, a 16.1% reduction, with
non-overlapping run ranges. Whole-frame total-span p95 remains inconclusive.
The change removes 91 unnecessary transform wrappers at the sampled endpoint.

The button surface previously passed an identity matrix to `AnimatedContainer`.
Its only caller always supplied `Matrix4.identity()`. Removing that private
parameter lets Flutter omit its matrix tween and transform wrapper. The
production change deletes four lines in `lib/src/ui/components/d_button.dart`.

The surface retains its animated decoration, duration, easing, and immediate
hover and expanded-dismissal rules. Post-action press scaling remains in
`_DPostActionPrimitive` through its separate `AnimatedScale`. Public Native APIs,
layout, clipping, focus ownership, semantics, and hit-area policy are unchanged.

## Measurement

The base is `87430a57aad27e8b900ca43a40098c7e1c69b20a`. Both native bundles use
the unchanged `integration_test/topic_list_scroll_performance_test.dart` and
`tool/benchmark_topic_list_scroll.py`. The workload exercises production rows
with 3,000 topics, variable heights, event and assignment metadata, paged
restoration, and the existing 300-topic retention window.

The machine is an Apple M5 Pro with 18 CPU cores, macOS 26.6, and Flutter 3.47.7.
The profile builds use Metal Impeller, a 1280 by 860 logical viewport, and 2x
density. CPU sampling is enabled only in separate diagnostic captures. Timing
captures alternate baseline and candidate for five complete pairs under the
shared scroll-performance lock.

| Phase | Baseline build p95 median and range, ms | Candidate build p95 median and range, ms | Verdict |
| --- | --- | --- | --- |
| Ordinary downward | 3.405, 3.193 to 3.563 | 3.468, 2.164 to 3.574 | Inconclusive |
| Fast downward | 6.316, 5.906 to 6.857 | 5.300, 5.059 to 5.603 | Faster |
| Fast upward | 3.180, 3.075 to 3.534 | 3.211, 3.109 to 3.346 | Inconclusive |

Fast-downward total-span p95 has medians of 7.748 ms and 7.814 ms. Its ranges,
7.520 to 8.479 ms and 7.706 to 7.967 ms, overlap. Raster p95 stays near 0.7 ms.
The measured build-time saving does not establish lower whole-frame latency.
Row mounting and text layout remain the main sampled CPU costs.

All ten timing runs pass without discarded attempts, Flutter failures, or
comparison errors. Each phase sends 240 wheel events over four seconds.
Every run reaches the same titles, 1, 96, 671, then 82, and exactly the same
endpoint offsets, 9,600, 67,200, and 8,168 logical pixels. The runner checks
rendered titles, input counts, viewport, density, and scroll distance. The
workload uses synthetic topics and modeled page latency, so these results do
not measure live-network performance or trackpad momentum.

The [comparison data](data/button-surface-transform/comparison.json) retain
every run, all phase metrics, and both compiled framework hashes. Background
desktop applications remain running. Load averages are 3.14, 5.45, and 4.84
at the start, and 3.22, 4.30, and 4.46 at the end, on 18 CPU cores. The shared
lock spans the entire alternating command. Process snapshots before and during
the comparison show no unrelated release compiler running.

## Structural reduction

The diagnostic captures reach the same topic titles, 1, 96, 671, then 82.
At the fast-downward endpoint, both versions retain 15 mounted topic rows.
The census changes as follows:

| Resource | Baseline | Candidate |
| --- | ---: | ---: |
| Button surfaces | 91 | 91 |
| Animated containers | 121 | 121 |
| Transform widgets | 108 | 17 |
| Mounted elements | 11,563 | 11,472 |
| Ticker-capable states | 487 | 487 |

The fast-upward endpoint also loses exactly 91 transform widgets and elements.
The ordinary-downward endpoint has 86 button surfaces and loses 86 transforms.
Each removed `Transform` owns a `RenderTransform`. Flutter's
`AnimatedContainerState` also stops allocating and evaluating a `Matrix4Tween`
for each button surface when its `transform` is null. These are structural
changes, not measurements of retained heap bytes or allocated controllers.

In the separate fast-downward CPU captures, stacks containing `RenderTransform`
fall from 1.568% to 0.201% of samples. Upward shares are 1.273% and 0.041%.
Row mounting remains substantial, at 34.588% and 32.864% downward. Text layout
through `RenderParagraph` accounts for 13.108% and 12.364%. These inclusive
sample shares overlap and cannot be added or interpreted as elapsed-time
speedups. `Matrix4Tween` has no named samples in either capture, so the profile
does not quantify its allocation or interpolation cost separately.
The baseline diagnostic overlaps unrelated release compilation, which adds
uncertainty to sample-share comparisons. That compilation finishes before the
alternating timing captures begin.

The [census and attribution data](data/button-surface-transform/cpu-attribution.json)
preserve both complete widget counts and the sample-matching keys. Raw stacks
are retained for [baseline downward](data/button-surface-transform/baseline-fastDown.folded.gz),
[candidate downward](data/button-surface-transform/candidate-fastDown.folded.gz),
[baseline upward](data/button-surface-transform/baseline-fastUp.folded.gz), and
[candidate upward](data/button-surface-transform/candidate-fastUp.folded.gz).
The standard profiler tables are available for the
[baseline](data/button-surface-transform/baseline-cpu.txt) and
[candidate](data/button-surface-transform/candidate-cpu.txt).

## Verification

The focused widget run passes 179 tests across the files below. One existing
failure remains in `d_button_group_shared_outline_test.dart`.
`quiet paths share one flat well and leave separators passive` expects a
36-point height and receives 44. The identical failure reproduces with
`d_button.dart` restored byte-for-byte from base commit `87430a57a`.

The passing tests cover button bounds and edge taps, keyboard and link
semantics, borrowed focus ownership, animated focus rings, immediate hover,
expanded triggers, reduced motion, Native touch targets, post-action controls,
and topic-list construction and ticker behavior. No new tests or production
test hooks are needed for the removal. Targeted `dart analyze` reports no issues.

```sh
python3 /private/tmp/discourse-native-scroll-locked.py flutter test \
	test/d_button_test.dart \
	test/d_button_reference_test.dart \
	test/d_button_inline_metadata_test.dart \
	test/d_button_transparent_background_test.dart \
	test/d_button_resume_test.dart \
	test/d_button_group_test.dart \
	test/d_button_group_shared_outline_test.dart \
	test/post_action_buttons_mockup_parity_test.dart \
	test/app_touch_targets_test.dart \
	test/ui/d_touch_target_test.dart \
	test/topic_list_scroll_performance_test.dart

python3 /private/tmp/discourse-native-scroll-locked.py \
	dart analyze lib/src/ui/components/d_button.dart
```

## Reproduction

Create two isolated checkouts at the base. Apply the four-line removal only in
the candidate. Run each build from its checkout through the shared helper:

```sh
python3 /private/tmp/discourse-native-scroll-locked.py \
	flutter pub get

python3 /private/tmp/discourse-native-scroll-locked.py \
	env XCODE_XCCONFIG_FILE=/private/tmp/fast-topic-profile.xcconfig \
	flutter build macos --profile --no-pub \
	--target integration_test/topic_list_scroll_performance_test.dart

ditto build/macos/Build/Products/Profile/Discourse.app /tmp/button-baseline.app
```

Use `/tmp/button-candidate.app` for the candidate copy. The temporary xcconfig
contains `CODE_SIGNING_ALLOWED = NO`, `CODE_SIGNING_REQUIRED = NO`,
`ARCHS = arm64`, and `ONLY_ACTIVE_ARCH = YES`. Repository signing settings stay
unchanged. Preserve both bundles before starting comparisons:

```sh
python3 /private/tmp/discourse-native-scroll-locked.py caffeinate -di \
	python3 tool/benchmark_topic_list_scroll.py \
	--baseline /tmp/button-baseline.app --candidate /tmp/button-candidate.app \
	--runs 5 --output /tmp/button-comparison

python3 /private/tmp/discourse-native-scroll-locked.py caffeinate -di \
	python3 tool/benchmark_topic_list_scroll.py \
	--baseline /tmp/button-baseline.app --cpu --output /tmp/button-baseline-cpu

python3 /private/tmp/discourse-native-scroll-locked.py caffeinate -di \
	python3 tool/benchmark_topic_list_scroll.py \
	--baseline /tmp/button-candidate.app --cpu --output /tmp/button-candidate-cpu
```

Original bundles, logs, and captures are under
`/private/tmp/discourse-button-transform/`.
