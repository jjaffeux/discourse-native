# Topic-list restoration scheduling

Fast downward scrolling is **faster** with forward viewport lookahead. Across five
alternating native runs per version, frame-build p95 fell from a median **6.449 ms
to 4.172 ms (35.3%)**, with non-overlapping ranges. Visible-gap frames fell from a
median **93 to 11** during the four-second fast-downward phase.

Ordinary and reverse scrolling remain inconclusive. All ten final runs reached
the same topics and offsets, with identical page-request counts and no failures,
retries, or comparison errors. Backward lookahead was tested and rejected because
it changed the upward scroll trajectory; no correctness tolerance was relaxed.

This investigation separates restoration latency from row-construction cost. The
baseline is `87430a57a`, including the earlier fast-scroll work. It uses a fresh
native macOS profile build of the production topic-list harness.

## Results

The same native macOS Metal Impeller harness ran at 1280 × 860 logical pixels and
2× density. Timing captures disabled CPU sampling.

| Phase | Baseline build p95 median (range), ms | Candidate build p95 median (range), ms | Verdict |
| --- | --- | --- | --- |
| Ordinary downward | 3.105 (3.098–3.142) | 3.053 (2.830–3.231) | Inconclusive |
| Fast downward | 6.449 (6.108–7.266) | 4.172 (3.723–4.457) | Faster |
| Fast upward | 4.058 (3.577–4.616) | 3.525 (3.079–3.803) | Inconclusive |

Fast-downward frame total-span p95 fell from 7.895 ms (7.677–8.940) to 5.036 ms
(4.381–5.351). Raster p95 remained around 0.7 ms. The build-time percentage is
not a whole-frame or whole-application speedup.

| Phase | Baseline frames with unloaded visible rows, median (range) | Candidate |
| --- | --- | --- |
| Ordinary downward | 0 (0–0) | 0 (0–0) |
| Fast downward | 93 (91–98) | 11 (8–21) |
| Fast upward | 56 (55–56) | 56 (55–56) |

Fast-downward visible gaps occupied a median 19.38% of sampled frames before and
2.28% afterward. These counts measure visible feed backing after layout, including
frames between wheel updates; they are not counts of slow frames.

Every timing run reached topics 1 → 96 → 671 → 82 at offsets
0 → 9,600 → 67,200 → 8,168. Each side requested exactly 3, 19, and 11 pages in the
three phases. Every phase retained 300 topics. Restoration starts earlier without
reducing the amount of requested content.

[Comparison data](data/topic-list-restoration-scheduling/comparison.json) includes
all ten run reports and both compiled framework hashes.
[Gap summaries](data/topic-list-restoration-scheduling/visible-gaps.json) preserve
counts and rates. The synthetic workload models 50 ms page latency; it does not
measure live-community throughput or trackpad momentum.

## Baseline diagnosis

A separate CPU-sampled run fetched 3 pages during ordinary downward scrolling,
19 consecutive pages during fast downward scrolling, and 11 pages during fast
upward scrolling. This steady wheel workload did **not** demonstrate a large
obsolete FIFO backlog. Controlled transport tests separately exercise rapid
viewport replacement while opaque cursor replay is pending.

Fast-downward inclusive sample shares were 32.01% for `Element.inflateWidget`,
13.13% for `RenderParagraph`, and 8.51% for `_InactiveElements._unmount`.
`TopicFeedController._performRanges` accounted for 0.04%. Fast upward showed
similar attribution. Inclusive shares overlap and must not be added together;
these are diagnostic samples, not elapsed-time speedups. Row construction and
text layout remain the principal CPU costs.

The final candidate still spends about 32% of fast-downward inclusive CPU samples
in widget inflation and 12% in paragraph layout. Its range worker accounts for
0.04%, with `restoreViewport` at 0.12%. Sample totals and attribution are similar
to the baseline: this change moves restoration work away from visible gaps; it is
not evidence of a comparable reduction in total CPU work.

[CPU attribution](data/topic-list-restoration-scheduling/cpu-attribution.json),
[baseline tables](data/topic-list-restoration-scheduling/baseline-cpu.txt), and
[candidate tables](data/topic-list-restoration-scheduling/candidate-cpu.txt)
retain the separate diagnostic captures. Full collapsed stacks are preserved for
[downward before](data/topic-list-restoration-scheduling/baseline-fastDown.folded.gz),
[downward after](data/topic-list-restoration-scheduling/candidate-fastDown.folded.gz),
[upward before](data/topic-list-restoration-scheduling/baseline-fastUp.folded.gz), and
[upward after](data/topic-list-restoration-scheduling/candidate-fastUp.folded.gz).
The baseline diagnostic predates the added visible-gap counter; neither diagnostic
is used for timing claims.

## Scheduling behavior

- Explicit `ensureRange` requests remain queued until served or an existing
  error/cancellation boundary completes them. The old queue-length truncation
  could discard legitimate awaited requests. Awaited completion is independent
  of subsequent viewport/lookahead work, so keyboard callers can use restored
  rows before speculative work changes retention.
- Each retained panel owns its latest visible range. A scroll replaces only
  that panel's pending work; releasing it removes its remaining speculative
  work. Visible ranges across panels precede lookahead. Explicit requests take
  precedence and can interrupt speculative replay between page requests.
- Forward lookahead covers at most one viewport, capped at 30 rows and one
  quarter of the retention budget. Reverse scrolling restores the current visible
  and built cache rows. Lookahead does not pin additional rows. The production
  retention budget remains 300 topics.
- An obsolete replay stops before issuing another page request. A page already
  received still goes through the existing shape, duplicate, cursor, visible-row,
  personalization, and account/session validation before publication.
- Errors still stop automatic restoration until an explicit retry. Refresh and
  account cancellation still retire the old request. Multiple panels keep their
  independent visible-row protection.

The row builder coalesces missing mounted cache rows within the current frame.
Those rows become lower-priority work owned by the current viewport, so they can
finish restoring without retaining obsolete work after a jump. Scroll notifications
publish the visible range directly, allowing restoration before a skeleton enters
view. Row composition and Native component implementations are outside this
change.

## Rejected backward lookahead

Five alternating runs per version tested bidirectional lookahead. It reduced
skeleton exposure, but the upward endpoint changed from topic 82 in all five
baseline runs to topics 94–95. The same wheel input caused fewer corrections to
estimated row heights (ending at offsets 9,408–9,510 instead of 8,168). That is a
changed scroll trajectory, even though both stayed within the distance tolerance.
The unchanged content comparison rejected the candidate. The final version limits
lookahead to forward scrolling and preserves reverse mounted-row restoration;
it passes the original content gate across all five final pairs.

[Rejected comparison](data/topic-list-restoration-scheduling/bidirectional-rejected.json)
retains all runs, changed endpoints, and the comparison error. These timings are
not accepted performance evidence. No comparison tolerance was changed.

## Measurement and reproduction

The unchanged input workload has 3,000 mixed-height topics, 30 topics per page,
50 ms modeled page latency, a 300-topic retention budget, and 240 wheel events per
phase over four seconds (+40, +240, and -240 logical pixels). Both revisions use
the same additional harness counters: requested page paths and, after layout,
frames whose visible source range still contains an unloaded row. The gap counter
runs only during the input interval; it reports feed backing rather than scanning
or timing widget construction. Existing native geometry, scroll distance, title,
input count, error, and frame-count checks remain in force. Each phase additionally
checks that no more than 300 topics are retained.

All builds, tests, native captures, the complete alternating comparison, and the
final main-checkout merge use `/private/tmp/discourse-native-scroll-locked.py`.
Timing captures disable CPU sampling. CPU diagnostics are separate runs. The
machine has 18 logical CPUs; unrelated desktop applications and a separate
packaging job remained running, so alternating captures are necessary to limit
drift. The comparison records every pair and rejects changed content or distance.

Unsigned local builds use `XCODE_XCCONFIG_FILE=/private/tmp/fast-topic-profile.xcconfig`
with signing disabled, `ARCHS=arm64`, and `ONLY_ACTIVE_ARCH=YES`. Repository signing
settings are unchanged.

```sh
python3 /private/tmp/discourse-native-scroll-locked.py \
  env XCODE_XCCONFIG_FILE=/private/tmp/fast-topic-profile.xcconfig \
  flutter build macos --profile --no-pub \
  --target integration_test/topic_list_scroll_performance_test.dart
# Preserve each complete app bundle with ditto, then compare under one lock:
python3 /private/tmp/discourse-native-scroll-locked.py caffeinate -di \
  python3 tool/benchmark_topic_list_scroll.py \
  --baseline /private/tmp/topic-restoration-evidence/baseline.app \
  --candidate /private/tmp/topic-restoration-evidence/forward.app \
  --output /private/tmp/topic-restoration-evidence/forward-comparison
```

Original bundles, build/test logs, captures, and helper scripts are preserved under
`/private/tmp/topic-restoration-evidence/`.

## Verification

All 148 tests passed across these directly related files:

```sh
python3 /private/tmp/discourse-native-scroll-locked.py flutter test --no-pub \
  test/topic_feed_controller_test.dart \
  test/topic_list_view_lifecycle_test.dart \
  test/topic_list_cursor_coordinator_test.dart \
  test/topic_feed_selection_lifecycle_test.dart \
  test/topic_list_scroll_performance_test.dart
```

The new behavioral tests cover queue overflow, obsolete replay, release,
lookahead direction and bounds, explicit retry, awaited keyboard completion,
resuming cache work after preemption, two panels, refresh, and account replacement.
Restoring the old queue-length truncation makes the queue-overflow test fail at
its independent expected cursor. The existing mounted two-panel test caught an
intermediate regression where cached offscreen skeletons never finished restoring;
current cache restoration fixes that failure. The final candidate passes that
same test unchanged. The initial timing experiment used that intermediate
candidate and was interrupted and excluded; it is not evidence for the final
result.

Targeted analysis reported no issues, and `git diff --check` passed.

After rebasing onto main `a82c03d9a`, including the sibling button and row-composition
changes, the two affected UI suites passed all 49 tests and targeted analysis was
clean. A new native profile build and smoke capture reached the same topics and
offsets in every phase, retained 300 topics, and reported no Flutter errors.
[Integrated verification](data/topic-list-restoration-scheduling/integrated-verification.json)
records those checks and the combined binary hash. The timing comparison above
isolates this scheduler change against `87430a57a`; the combined main changes
were not benchmarked as a separate performance claim.
