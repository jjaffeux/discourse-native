# Fast desktop topic-list scrolling

Fast upward scrolling is measurably faster after reducing row construction and teardown costs. Across five alternating native runs per revision, frame-build p95 fell from a median **6.534 ms to 4.037 ms (38.2%)**, with non-overlapping run ranges. Frame total-span p95 also improved, from 7.630 ms to 6.624 ms.

Fast downward scrolling's median frame-build p95 improved 10.8%, but its ranges overlap. That result remains inconclusive. The harness retains downward scrolling as its primary phase, so its overall verdict is `inconclusive`; the per-phase report records the clear upward improvement.

## Results

The baseline is `a58cbb376`, including the [earlier metadata-width improvement](topic-list-scrolling.md). These are new captures on the Apple M5 Pro, using the native macOS Metal Impeller engine, a 1280 × 860 logical window, and 2× density.

| Phase | Baseline build p95, median (range), ms | Candidate build p95, median (range), ms | Verdict |
| --- | --- | --- | --- |
| Ordinary downward | 2.751 (2.277–3.069) | 2.369 (2.023–2.965) | Inconclusive |
| Fast downward | 7.452 (6.627–7.573) | 6.646 (6.253–6.758) | Inconclusive |
| Fast upward | 6.534 (6.405–6.607) | 4.037 (3.204–4.106) | Faster |

For fast upward scrolling, frame total-span p95 ranges were 7.487–8.094 ms before and 5.462–6.941 ms afterward. Raster p95 stayed around 0.7 ms. The improvement is principally CPU work, and the build-time percentage must not be interpreted as the same percentage reduction in the whole frame.

[Comparison data](data/fast-topic-list-scrolling/comparison.json) preserves all ten run reports, per-phase verdicts, and both compiled framework hashes. CPU sampling was disabled for these timings. Background desktop applications remained running; builds were alternated to limit drift. All five final pairs passed, without retries, Flutter failures, or comparison errors.

## Construction and teardown

The sampled fast-downward endpoint contains 15 cached topic rows. The widget census changed as follows:

| Resource | Before | After |
| --- | ---: | ---: |
| Mounted elements | 13,153 | 11,563 |
| State objects implementing `TickerProvider` | 847 | 487 |
| Largest group reading the same ticker-mode notifier | 843 | 35 |

The census counts ticker-capable states, including unopened previews; it is not an exact count of allocated animation controllers. The full census and CPU attribution are in [CPU data](data/fast-topic-list-scrolling/cpu-attribution.json).

Three changes address the measured costs:

- Each topic row now has its own `TickerMode` notifier. Flutter's animation states remove listeners by searching and compacting notifier arrays. Keeping the cohort within one row avoids repeatedly searching the listeners of every visible row during teardown. The scope continues to inherit disabled tickers and forced-frame settings from its page.
- The existing `DButtonDensity.inlineMetadata` implementation uses a compact focus/tap owner inside the Native kit. It resolves the same Native `ButtonStyle`, painted surface, typography, dimensions, and states, while avoiding the Material button, theme, and ink lifecycles around every metadata action. The public component API and its touch-target wrapper remain the same.
- Closed `DPopover` instances retain resources only when needed. Previously, rebuilding an unopened popover initialized its animation, and disposing an unopened popover could initialize an animation merely to dispose it. Unused content/menu focus nodes and borrowed-controller fallbacks now remain unallocated too. This follows the kit's existing Hover Card and Tooltip resource pattern.

In the separate diagnostic captures, listener removal fell from 5.11% to 0.45% of fast-downward CPU samples and from 7.54% to 0.36% of fast-upward samples. `_InactiveElements._unmount` fell from 14.92% to 9.11% downward and from 16.27% to 9.55% upward. These are single-run inclusive sample shares, not elapsed-time speedups; overlapping call paths must not be added together.

New-row mounting and text layout remain substantial. The optimization reduces their supporting widget and resource lifecycles; it does not eliminate construction bursts when restored pages replace visible skeleton rows.

## Traces

The overview flame graphs retain selected work-bearing Dart callers, attribute native work to those callers, and collapse recursion. Hover over a block for its complete name and sample count.

| Direction | Before | After |
| --- | --- | --- |
| Fast downward | [Flame graph](data/fast-topic-list-scrolling/baseline-fastDown.svg) | [Flame graph](data/fast-topic-list-scrolling/candidate-fastDown.svg) |
| Fast upward | [Flame graph](data/fast-topic-list-scrolling/baseline-fastUp.svg) | [Flame graph](data/fast-topic-list-scrolling/candidate-fastUp.svg) |

Unfiltered collapsed stacks are retained for [downward before](data/fast-topic-list-scrolling/baseline-fastDown.folded.gz), [downward after](data/fast-topic-list-scrolling/candidate-fastDown.folded.gz), [upward before](data/fast-topic-list-scrolling/baseline-fastUp.folded.gz), and [upward after](data/fast-topic-list-scrolling/candidate-fastUp.folded.gz). The [before](data/fast-topic-list-scrolling/baseline-cpu.txt) and [after](data/fast-topic-list-scrolling/candidate-cpu.txt) CPU tables include all three phases.

## Workload and reproduction

The same production topic-list harness loads 3,000 mixed-height topics through 100 normal pages, with the production 300-topic retention window and modeled 50 ms page latency. It includes categories, tags, status icons, avatar fallbacks, events, and assignments. Each phase delivers 240 wheel events over four seconds: +40, +240, then −240 logical pixels per event.

Every final run reached the same rendered topics, 1 → 96 → 671 → 82. Downward offsets matched exactly; upward offsets ended at 8,168 or 8,180 logical pixels while the list corrected estimated heights. This is within the frozen 5% distance tolerance. The runner also checks native viewport/density, input counts, substantial scrolling, actual rendered titles, and Flutter errors. The workload uses synthetic topics and page latency; it does not measure live-forum requests or trackpad momentum.

Build both revisions with the same harness and preserve their complete bundles:

```sh
flutter build macos --profile --no-pub \
  --target integration_test/topic_list_scroll_performance_test.dart
ditto build/macos/Build/Products/Profile/Discourse.app /tmp/topic-list-candidate.app
```

Compare without sampling, then collect CPU diagnostics separately:

```sh
caffeinate -di python3 tool/benchmark_topic_list_scroll.py \
  --baseline /tmp/topic-list-baseline.app \
  --candidate /tmp/topic-list-candidate.app \
  --output /tmp/topic-list-comparison

caffeinate -di python3 tool/benchmark_topic_list_scroll.py \
  --baseline /tmp/topic-list-candidate.app --cpu \
  --output /tmp/topic-list-candidate-cpu
```

The unsigned local builds used the temporary signing/architecture configuration described in the earlier report. Repository signing settings were unchanged. Original bundles, captures, and logs remain under `/private/tmp/discourse-fast-topic-scroll/`.

Exploratory native captures encountered startup or cleanup timeouts and were rejected. The timing runner now retries a whole baseline/candidate pair after a timeout, up to three attempts, recording discarded attempts. Assertion failures and other workload errors still abort. The final comparison needed no retries; the final successful CPU capture followed one rejected cleanup timeout.

## Verification

- Both new popover allocation regressions failed on the baseline, each observing an unwanted `AnimationController`, and passed after the repair. All 38 popover tests passed.
- The eight new inline-button contract checks pass on both the old and new implementations. They cover pointer and keyboard activation, action/link semantics, disabled behavior, animated keyboard focus, hover/cancellation, and matching desktop/iOS geometry at 1× and 2× text scale.
- The main focused run passed 498 tests, with two existing responsive-toolbar GlobalKey failures. The consumer run passed 45 tests, with two existing status-sheet inset failures. All four failures reproduced with every production change restored to unchanged `a58cbb376`.
- A final ten-test run passed the inline-button contracts, connected topic-list accessibility tree, and application touch-target checks. Targeted Dart analysis, Python compilation, and `git diff --check` passed.

Only directly related test files were run. The Native kit API, hit-area policy, pagination, and feed retention budget remain unchanged.
