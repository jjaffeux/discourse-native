# Desktop topic-list scrolling

The later [fast-scroll construction and teardown report](fast-topic-list-scrolling.md) records the follow-up improvements.

Ordinary wheel scrolling has a reproducible frame-build improvement after sharing metadata text measurements between topic rows. Its p95 fell from a median **3.529 ms to 3.185 ms (9.7%)** across five alternating native macOS runs per revision. The run ranges do not overlap. Fast downward scrolling remains inconclusive: its median improved, but the ranges overlap.

## Evidence

The [before flame graph](data/topic-list-scrolling/baseline-fastDown.svg) and [after flame graph](data/topic-list-scrolling/candidate-fastDown.svg) show CPU samples from separate diagnostic runs. Hover over a block to see its full name and sample count. These overview graphs retain selected Dart callers, attribute native work to those callers, and collapse recursion. They are not elapsed-time timelines.

Full unfiltered stacks are retained as [before](data/topic-list-scrolling/baseline-fastDown.folded.gz) and [after](data/topic-list-scrolling/candidate-fastDown.folded.gz) collapsed-stack files. The [before CPU tables](data/topic-list-scrolling/baseline-cpu.txt) and [after CPU tables](data/topic-list-scrolling/candidate-cpu.txt) include all three phases. [Comparison data](data/topic-list-scrolling/comparison.json) contains every timing run and both compiled framework hashes.

All measurements used an Apple M5 Pro with 18 CPU cores, macOS 26.6, the native Metal Impeller engine, and a 1280 × 860 logical viewport at 2× density. The baseline was `628b947c7`. Background desktop applications remained running; alternating builds reduces drift, and the ranges below preserve the observed variation.

| Wheel phase | Baseline build p95, median (range), ms | Candidate build p95, median (range), ms | Verdict |
| --- | --- | --- | --- |
| Ordinary downward | 3.529 (3.440–3.624) | 3.185 (3.125–3.241) | Faster |
| Fast downward | 8.568 (7.792–9.353) | 7.786 (7.327–8.294) | Inconclusive |
| Fast upward | 7.581 (7.440–7.678) | 7.362 (7.193–7.778) | Inconclusive |

The runner keeps fast downward scrolling as its primary phase, so its overall verdict remains `inconclusive`. The ordinary-scroll improvement is a distinct, repeatable result. CPU sampling was disabled for all ten timing runs.

## Bottlenecks and change

The UI thread is the limiter in this workload. Fast downward raster p95 stayed around 0.8 ms, while frame-build p95 reached roughly 8–9 ms. The baseline CPU diagnostic attributes 37.8% of samples to layout and 34.2% to widget inflation. Those inclusive call paths overlap and must not be added together.

Three costs stand out:

- New rows mount many interactive descendants and lay out their text. Restored pages can replace several visible skeletons in one frame, producing bursts of row construction.
- Row teardown is also substantial: `_InactiveElements._unmount` appears in 14.1% of fast-downward samples. Removing animation listeners accounts for part of that cost. This remains a bottleneck.
- Each new footer previously created its own width cache, so common category names, tags, count labels, and ages were shaped again as rows entered the viewport. `TopicTextMeasurements.measure` appears in 3.85% of fast-downward samples before the change and 0.09% afterward. Ordinary downward samples fell from 2.40% to 0.28%. These are single-run diagnostic sample shares, not speedup estimates.

`TopicListView` now owns the existing bounded width cache, and its footers reuse it. The cache still retains at most 128 strings for one typography configuration. Feed/account identity changes, font notifications, site retirement, and list disposal clear it. Typography changes continue to invalidate it through the existing configuration key. Standalone topic rows keep their own caches.

The change preserves the Native components, interactive targets, row layout, and the feed's 300-topic retention limit. It does not resolve all fast-scroll construction and teardown costs.

## Workload and correctness

`integration_test/topic_list_scroll_performance_test.dart` exercises the production list and row widgets with 3,000 variable-height topics loaded through 100 normal pages. It includes category breadcrumbs, tags, avatar fallbacks, event dates, assignments, and status icons. The fake transport adds 50 ms to each page response so evicted-page restoration runs asynchronously.

Three four-second phases send 240 actual wheel events each, at approximately 60 inputs per second: +40, +240, then −240 logical pixels. The mouse stays over the list. The harness uses the native window size, loads the bundled fonts, dismisses the launch screen, checks substantial scroll displacement and different rendered titles, and rejects Flutter errors or interrupted runs. Only about 9–10 titles remain mounted at each phase endpoint.

Every timing run traversed the same endpoint topics: 1 → 96 → 671 → 82. Variable-height restoration corrects estimated offsets during the upward phase, so the harness permits a 5% displacement correction. The comparison independently checks input counts, scroll-distance variation within 5%, matching viewports, and reached-topic variation within two rows. All ten runs passed, with zero comparison errors.

This is a controlled rendering workload with synthetic topics and page latency. It does not measure a live forum, avatar downloads, or trackpad momentum. Semantics are checked by the focused widget suite; the native performance workload disables semantics traversal.

## Reproduce

Use the same harness in both source revisions. Build each revision and preserve its full bundle before building the next:

```sh
flutter pub get
flutter build macos --profile --no-pub \
  --target integration_test/topic_list_scroll_performance_test.dart
ditto build/macos/Build/Products/Profile/Discourse.app /tmp/topic-list-baseline.app
```

For this local unsigned build, a temporary `XCODE_XCCONFIG_FILE` set `CODE_SIGNING_ALLOWED = NO`, `CODE_SIGNING_REQUIRED = NO`, `ARCHS = arm64`, and `ONLY_ACTIVE_ARCH = YES`. Repository signing settings were unchanged.

After preserving the candidate bundle, compare without sampling:

```sh
python3 tool/benchmark_topic_list_scroll.py \
  --baseline /tmp/topic-list-baseline.app \
  --candidate /tmp/topic-list-candidate.app \
  --output /tmp/topic-list-comparison
```

Capture CPU samples and generate flame graphs separately for each bundle:

```sh
python3 tool/benchmark_topic_list_scroll.py \
  --baseline /tmp/topic-list-baseline.app --cpu \
  --output /tmp/topic-list-baseline-cpu
```

The `--cpu` output contains raw response data, phase flame graphs, full compressed collapsed stacks, and CPU tables. Local original captures and process logs are retained under `/private/tmp/discourse-topic-list-profile/`.

## Validation

All 108 tests passed across these directly related files:

```sh
flutter test --no-pub \
  test/topic_text_measurements_test.dart \
  test/topic_card_taxonomy_layout_test.dart \
  test/topic_list_scroll_performance_test.dart \
  test/compact_topic_list_test.dart \
  test/topic_list_view_lifecycle_test.dart \
  test/topic_list_badge_categories_test.dart \
  test/topic_list_semantics_test.dart
```

Targeted Dart analysis, Python compilation, and `git diff --check` passed. Both native CPU diagnostics and all ten native timing runs completed their workload assertions.
