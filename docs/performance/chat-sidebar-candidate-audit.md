# Chat sidebar and topic-layout follow-up — September 22

Investigated the three candidates from the live debug CPU sample after
`3661cd6ef`: topic sliver layout, plugin sidebar section construction, and chat
destination/unread calculations. A fresh connection to the restarted debug app
was also checked; its mostly-startup sample did not establish another hotspot.
The fixes below follow reproducible work counts, not inclusive CPU percentages.

## Chat projection and sidebar totals

Priority filtering and sorting repeatedly scanned each channel's thread map.
Legacy public, starred, and direct-message ordering did the same; DM comparisons
also repeatedly searched for the oldest unread thread. Calculations now use
identity maps local to each sort. Identity keys matter because `ChatChannel`'s
value hash itself traverses its thread map. Nothing survives a projection call,
so changed channel data, view times, preferences, and accounts remain fresh.

Sidebar unread totals previously called sorted channel-list getters, including
DM activity sorting. Totals now select the original public/direct source and
filter membership without sorting. Message counts, watched-thread message
counts, muted memberships, and starred partitioning retain their prior meaning.
Thread counts and overlapping mentions are still excluded from these totals.

Tests use 64 channels with 32 thread records each and count collection visits,
including entry visits caused by hashing. All five performance regressions fail
against `3661cd6ef` and pass after the change:

| Operation | Baseline visits | Fixed bound |
| --- | ---: | ---: |
| Unread filter plus priority sort | 31,680 | 2,048 |
| Public activity sort | 9,728 | 2,048 |
| Starred activity sort | 34,048 | 2,048 |
| DM activity sort | 68,096 | 4,096 |
| DM section message total | 41,728 | 0 |

The priority regression also changes the thread data between projections to
check freshness. Existing ordering tests cover urgency, view-time boundaries,
oldest-thread tie breaking, activity dates, stable order, and display limits.

## Complete sidebar section generation

The diagnostic harness exercises `PluginRegistry.sidebarSections`, including
plugin ownership wrappers and `ChatPlugin.destination`, using 100 public and
75 DM channels, 32 thread records each, and priority ordering in all sections.
It produces 169 destinations after the existing DM display cap and navigation
entries. After 100 warmups it measures 50 batches of 20 synchronous calls.

| Debug harness, microseconds per call | Baseline | Fixed |
| --- | ---: | ---: |
| Median | 1,836.10 | 481.15 |
| p95 batch average | 1,957.95 | 969.30 |

These are one pair of debug microbenchmarks on macOS, not native frame timings
or a measured whole-app speedup. The deterministic work-count reductions are
the stronger evidence. Reproduce with:

```sh
flutter test --no-pub tool/chat_sidebar_benchmark_test.dart
```

The generic section/destination construction remains proportional to the
returned rows. Its callbacks retain build contexts and plugin ownership, so
this investigation does not justify caching those objects across builds.
Core sidebar sections already have an instance/custom-section identity cache.
Plugin sections refresh through their advertised listenables and inherited
context; keyboard action lookup also constructs them for eligible modified-key
events. Their derived chat work benefits from the fixes above.

## Topic layout

Ran the existing production-reader fixture in a separate macOS profile build:

```sh
flutter build macos --profile -t tool/topic_scroll_profile_main.dart \
  --dart-define=SCROLL_MIXED=true --dart-define=SCROLL_LABEL=candidate-audit
```

Flutter 3.47.4 / Dart 3.13.3, arm64, Skia, 120 Hz, DPR 2; the visible fixture
used a 2560 × 1049 logical viewport. Each pass contains four alternating
120 × 80-pixel scroll legs through synthetic rich replies. Semantics were
enabled and unchanged. The harness does not enforce a foreground gate; it was
raised for capture. This is a diagnostic run, not a baseline/fix comparison.

| Measurement | First pass | Return pass |
| --- | ---: | ---: |
| Frames | 542 | 544 |
| UI p95 / p99 | 2.38 / 5.27 ms | 1.92 / 4.78 ms |
| Maximum UI frame | 8.07 ms | 8.92 ms |
| UI frames above 8.33 ms | 0 | 1 |
| Raster frames above 8.33 ms | 3 | 0 |
| Viewport bookkeeping p95 | 143 µs | 174 µs |
| Post layouts | 50 | 24 |
| Whole-topic builds | 1 | 0 |

There is one sliver-layout change per commanded scroll step, not an unexplained
layout loop. The wider viewport crosses the existing bounded reply-retention
window: 16 rows reattach on the return pass. Its one slow UI frame includes a
newly attached post with 3.12 ms of layout. The initial raster outliers are
predominantly outside the recorded engine rendering phases; the capture does
not identify their native cause. CPU sampling was disabled in this standalone
profile launch. No topic-layout change is supported by these results.

Capture summaries and the slow-frame details are retained in
[chat-sidebar-candidate-audit.json](chat-sidebar-candidate-audit.json).

## Verification

The focused suite passes 292 tests across chat projection/controller behavior,
sidebar widgets and panel switching, session changes, and topic scroll churn,
including prepend anchoring and retained reply reuse. Changed Dart files and
the benchmark pass static analysis. No public UI-kit API or appearance changes.
