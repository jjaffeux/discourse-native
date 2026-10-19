# Command search benchmark

Run from the repository root with a revision that contains the uncached command scorer.

```sh
python3 tool/benchmark_command_search.py \
  --baseline 080f5c2ea78976164cd98d5d7ac90a45e2f05efe \
  --output /tmp/command-search-benchmark \
  --widget --profile
```

When other performance sessions share this machine, run the entire command through their validation lane.

The script extracts the actual `_score` methods and search helpers from the baseline revision and current source. It supplies minimal item and scope types, then compiles both implementations into one release AOT executable. The measured work includes filtering, stable score sorting, result materialization, and a consumed checksum. It compares every result's value, score, and order before measuring.

Each vocabulary contains 250, 2,000, or 10,000 items with category labels and three aliases. Queries cover blank input, whitespace, prefixes, many matches, token fallback, a specific alias, and no ordinary matches. Forced rows remain visible. Each case warms both implementations and records six alternating samples. A separate cold-query case constructs a fresh search cache each iteration.

`--widget` also runs both complete command implementations in one Flutter widget-test process. The temporary baseline library comes from the requested revision. Both sides open the list, apply eight query changes, and activate a result. Five alternating measured rounds follow one warmup round. Opening, total query time, and selection time are reported separately. Temporary source files are removed after the run.

These widget times include debug assertions, test binding overhead, layout, and painting. They corroborate the CPU result and exercise the real command path. They do not measure release UI latency or physical-device frame rate.

`--profile` captures a separate baseline JIT CPU sample profile to locate repeated search work. That trace is excluded from AOT timing samples.

The output directory contains source snapshots, exact revision and source-hash metadata, machine load and SDK details, raw AOT samples, optional widget logs and CPU samples, and `summary.json` with medians and ranges. Retain this directory when citing a result. The matching behavior and keyboard reveal contract are covered by `test/ui/d_command_test.dart`.

## Recorded measurements on 2026-10-19

The baseline was `080f5c2ea78976164cd98d5d7ac90a45e2f05efe`, which already mounted long lists lazily. The candidate used cached search snapshots and deferred row builders. The run used Dart 3.13.5 on macOS ARM64, with 18 CPU cores. Unrelated Godot and browser processes remained active. Load averages were 12.01, 16.66, and 15.10 at the start.

Release AOT search preparation for `category 19` produced these medians and ranges in milliseconds across six alternating samples per side.

| Options | Baseline | Candidate | Median reduction |
| --- | --- | --- | --- |
| 250 | 0.281, range 0.268 to 0.283 | 0.068, range 0.065 to 0.074 | 76% |
| 2,000 | 2.186, range 2.129 to 2.208 | 0.593, range 0.542 to 0.610 | 73% |
| 10,000 | 11.857, range 11.404 to 12.186 | 4.676, range 4.062 to 5.247 | 61% |

Fresh-cache preparation also improved. At 2,000 options, the median fell from 2.196 ms, range 2.179 to 2.239, to 1.323 ms, range 1.251 to 1.386. The separate baseline JIT profile contained 4,057 CPU samples. `_defaultCommandFilter` appeared in 3,359 stacks and `_score` in 3,838. Repeated normalization, joining, substring matching, and token preparation occupied the measured CPU path. The candidate still scans items and sorts matching results.

The paired widget workload passed all 36 cases with correct activation. Its total time for eight query updates at 10,000 options had a baseline median of 252 ms, range 204 to 383, and a candidate median of 185 ms, range 151 to 250. The candidate was faster in each of the five measured pairs, but the broad ranges limit the size of the end-to-end claim. At 250 and 2,000 options, widget latency differences were inconclusive. Opening and selection timings were also noisy. The accepted improvement is the release CPU search preparation result, with large-list widget evidence as corroboration.

Raw artifacts for this run are in `/private/tmp/discourse-native-perf-20261019-01a153f7/08/paired`. The captured candidate source has SHA-256 `814c8a26b950111f64a1e787104692686bff54499146511a51f285dd0afad9fc`. Complete score and order comparisons passed with zero errors. No physical-device measurement was made.
