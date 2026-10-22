# Topic feed identity reconciliation

This benchmark measures the production `TopicFeedController.loadMore` and
`ensureRange` futures with prebuilt, immediately completed API responses.
It includes credentials, lease checks, Store updates, page shape processing,
identity reconciliation, eviction, checkpoints, feed publication, and listeners.
Fixture creation, seed loads, response construction, verification, and disposal
happen outside the timer. Every resulting row, gap, cursor, retained count,
Store record, request count, and expected error is checked.

Build and run on macOS with the project's Flutter SDK.

```sh
flutter build macos --release --target tool/benchmark_topic_feed_insertion.dart
ditto build/macos/Build/Products/Release/Discourse.app /private/tmp/topic-feed-benchmark.app
printf '<plist version="1.0"><dict/></plist>' > /private/tmp/topic-feed-benchmark.entitlements
codesign --force --deep --sign - --entitlements /private/tmp/topic-feed-benchmark.entitlements /private/tmp/topic-feed-benchmark.app
FEED_BENCH_BATCH=32 /private/tmp/topic-feed-benchmark.app/Contents/MacOS/Discourse
```

The copied benchmark bundle uses ad hoc signing with empty entitlements for
local execution. Both comparison sides must use that signing configuration.

The executable prints JSON and exits nonzero on an unexpected result. Defaults
are six warmup samples, 30 measured samples, and 128 endpoints per sample.
`FEED_BENCH_SAMPLES` and `FEED_BENCH_BATCH` override the measured sample and batch
counts. Save separate baseline and candidate app bundles and alternate their
executables at least five times. Each sample reports the mean time per endpoint in its timed batch. Compare
the median of those batch means per launch, then the median and range across
launches. These are not individual-request percentiles.

The full workload uses 300 retained rows and 30-item pages. The short control
uses 20 rows and 10-item pages. The duplicate append contains 30 raw IDs with
20 unique IDs and 10 new IDs. Restores seed 330 rows, retain 300, and request an
evicted first page. Ordinary workloads use the default 32 checkpoints. Reordered
restore controls use three checkpoints to drop the saved page shape and
exercise identity reconciliation after a checkpoint has been dropped. Controls include a retained ID
moving to the restored page, reader and viewport protection, and a protected
identity move that must fail atomically.

Count retained entries visited by the exact production window body separately.
The script extracts the window and page-shape code from the selected revision,
replaces its map with an instrumented map, and compiles a temporary Dart AOT
executable. It counts entry visits in identity removal and restoration checks.
It also checks an early protected move and repeated-ID insertion/protection
behavior. It does not count hash lookups, allocation, trimming, or publication. Full
controller timing above includes those costs. A Dart SDK must be on `PATH`.

```sh
python3 tool/count_topic_feed_identity_work.py BASELINE_REVISION
python3 tool/count_topic_feed_identity_work.py
```

These are desktop controller CPU measurements with zero network delay. They do
not measure HTTP decoding, rendering, frame timing, device latency, or energy.

## Result recorded on 2026-10-22

The baseline was local main `3e64ee2a6adcc1415685c9b481c2825e2a7cb8cd`.
Its controller file matched `1c23479833847cf04c3a7ece4928d670fce700d8`.
Both sides used macOS release AOT, Flutter 3.47.7, Dart 3.13.5, and the same
benchmark driver on an 18-core host. The shared validation lane serialized
heavy checks. Five process runs per side alternated baseline then candidate.
Each run used six warmup batches and 30 measured batches of 32 endpoints.
All output checks passed. Each workload verified 4,800 measured endpoints per
side across the five runs, including the expected failures in the error control.

The table reports the median of five per-launch medians of batch means.
Bracketed ranges are the minimum and maximum of those five launch medians.
All values are microseconds per endpoint.

| Workload | Baseline median [range] | Candidate median [range] | Change |
| --- | --- | --- | --- |
| `append300` | 56.90 [54.70, 57.01] | 39.46 [37.99, 40.36] | -30.6% |
| `appendShort20` | 6.96 [6.79, 7.94] | 7.04 [6.78, 8.24] | +1.2% |
| `appendDuplicates300` | 40.06 [38.57, 41.07] | 34.57 [33.18, 35.31] | -13.7% |
| `restore300` | 382.59 [378.68, 396.66] | 105.69 [91.72, 118.04] | -72.4% |
| `restoreReordered300` | 395.98 [372.50, 398.49] | 107.68 [104.18, 131.76] | -72.8% |
| `restoreProtected300` | 420.89 [414.71, 438.48] | 119.67 [108.76, 122.10] | -71.6% |
| `restoreMovedProtectedError300` | 21.11 [20.56, 22.98] | 22.05 [21.48, 24.11] | +4.5% |

The retained-entry work profile identifies the removed identity scans. Append
visits fell from 9,435 to 300, and stable restore visits from 18,435 to 600.
An early protected move still visits one retained entry before rejection.
Temporary lookup construction and all unchanged controller work are included
in the endpoint timings. Store updates, trimming, checkpoints, and publication
remain, so fewer entry visits do not imply a proportional endpoint speedup.

Full-window append, overlap, and successful restores have separated run ranges.
The short-feed and early-error ranges overlap; no timing difference is
established for those controls. The normal restore saves about 0.277 ms of
controller processing in this zero-network workload. Network, rendering,
physical-device latency, allocation totals, heat, and battery were not measured.

The candidate controller source SHA-256 was
`c373757978355e1a08ff41fd8ba153ab8b0d935688f235234c6b3227d2817877`.
Focused verification ran `test/topic_feed_controller_test.dart` and
`test/topic_feed_hydration_test.dart`, including eviction after reordered replay
and atomic rejection of a late protected conflict. The source-derived counter
also checked repeated-ID final insertion order and protected duplicate rejection.

Per-launch medians used for the table follow.

```json
{
  "append300": {
    "baseline": [
      56.975906249999994,
      56.895828124999994,
      57.01171875,
      54.69921875,
      55.01628125
    ],
    "candidate": [
      39.458328125,
      40.3639375,
      39.995453125,
      38.695953125,
      37.988296875
    ]
  },
  "appendShort20": {
    "baseline": [
      6.9609375,
      7.2330781250000005,
      7.9387968749999995,
      6.7916718750000005,
      6.870453125
    ],
    "candidate": [
      6.8782499999999995,
      7.13409375,
      8.242843749999999,
      6.779296875,
      7.0442656249999995
    ]
  },
  "appendDuplicates300": {
    "baseline": [
      40.059234375,
      39.741546875,
      41.065109375,
      40.813796875,
      38.56771875
    ],
    "candidate": [
      35.309234375,
      34.865875,
      34.571609375,
      33.522140625000006,
      33.181640625
    ]
  },
  "restore300": {
    "baseline": [
      378.68425,
      387.9798125,
      396.65625,
      382.5891875,
      380.580078125
    ],
    "candidate": [
      105.68620312499999,
      113.76171875,
      118.041015625,
      91.715484375,
      105.4075625
    ]
  },
  "restoreReordered300": {
    "baseline": [
      372.50196875,
      398.25521875000004,
      398.48696875,
      376.280609375,
      395.979171875
    ],
    "candidate": [
      106.54948437499999,
      131.762390625,
      120.6484375,
      104.17512500000001,
      107.68034374999999
    ]
  },
  "restoreProtected300": {
    "baseline": [
      420.89321874999996,
      438.48046875,
      430.927078125,
      420.697265625,
      414.70571875
    ],
    "candidate": [
      119.66926562500001,
      119.327484375,
      108.75520312500001,
      122.10481250000001,
      119.875
    ]
  },
  "restoreMovedProtectedError300": {
    "baseline": [
      21.106125,
      22.82096875,
      22.981781249999997,
      20.69921875,
      20.5579375
    ],
    "candidate": [
      22.350265625,
      24.110687499999997,
      21.610671875,
      21.477859375,
      22.046890625
    ]
  }
}
```
