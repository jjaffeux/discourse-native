# Local tag search preparation

`searchFilterTags` reuses normalized local metadata from the existing immutable merged tag snapshot. The local projection is created after the remote response and current lease check. Remote results still take precedence, the last remote duplicate wins, descriptions keep their original numeric parsing, and every merged result is sorted. Category-scoped searches skip the local projection.

Five alternating runs per side measured the awaited production controller in Flutter 3.47.7, Dart 3.13.5, debug JIT. The baseline was `1c23479833847cf04c3a7ece4928d670fce700d8`. Immediate fake API responses remove network delay. The workload includes 30 and 5,000 known tags, three remote response generations, mixed queries, forced source refreshes, and first selective searches after refresh. Every output is checked against a separate full-order oracle and consumed outside the timer.

## Results

Times are total milliseconds per workload. Each cell gives the median and minimum to maximum across five runs. The primary result is the 320-query workload with 5,000 known tags, which used 54% less controller time. Its ranges do not overlap.

| Known tags | Workload | Baseline ms | Candidate ms |
| --- | --- | --- | --- |
| 5,000 | 320 searches on unchanged sources | 434.954, 358.901 to 768.195 | 200.331, 174.757 to 212.074 |
| 5,000 | Eight refreshes and 64 searches | 87.573, 83.783 to 125.338 | 52.645, 42.651 to 55.965 |
| 5,000 | Initial load and eight searches | 15.527, 11.607 to 26.485 | 11.329, 10.068 to 12.327 |
| 5,000 | Five refreshes, each followed by its first selective search | 5.055, 4.504 to 7.736 | 5.384, 4.482 to 6.979 |
| 30 | 320 searches on unchanged sources | 48.835, 29.465 to 55.817 | 29.119, 23.095 to 39.742 |
| 30 | Eight refreshes and 64 searches | 8.257, 5.845 to 12.442 | 6.538, 4.900 to 7.416 |
| 30 | Initial load and eight searches | 8.746, 6.497 to 16.634 | 10.195, 6.730 to 10.832 |
| 30 | Five refreshes, each followed by its first selective search | 0.683, 0.441 to 1.509 | 0.603, 0.464 to 0.771 |

The large-directory refresh workload includes cache maintenance and used 40% less time. First selective search timings and small-directory cold timings have overlapping ranges, so they show no clear difference. The large-directory first-selective median rose 0.329 ms across five refreshes, with mixed paired differences. No first-search speedup is claimed.

A separate instrumented run counted 6,501,144 to 32,240 lowercase calls and 18,354,826 to 32,000 integer parses across the 320 large-directory searches. Local entries are reused; remote descriptions are parsed once per response. Separate CPU sampling found sorting in 75% of baseline stacks and 64% of candidate stacks. Repeated conversion work largely disappeared; integer and string comparison still limit the remaining sort. Inclusive profile percentages overlap and must not be added.

This is controller CPU evidence in a test VM. It does not establish device latency, FPS, heat, battery, or network gains. Ordinary desktop background activity remained, and timing variability was substantial. The cache retains one normalized entry per public merged tag after the first unscoped search. Heap size was not measured.

The [machine-readable evidence](data/taxonomy-tag-search.json) includes all timing samples, ranges, checksums, exact source hashes, operation counts, and profile summaries. Raw logs and profile samples remain in the owner worktree under `.audit/taxonomy-tag-search/`.

## Reproduce

Prepare dependencies with the pinned Flutter SDK, then run the current controller benchmark:

```sh
TAXONOMY_TAG_SEARCH_OUTPUT=/tmp/taxonomy-tag-search.json flutter test --no-pub test/taxonomy_tag_search_benchmark_test.dart
```

Run the paired comparison from an isolated Git worktree containing this change:

```sh
python3 tool/benchmark_taxonomy_tag_search.py --baseline 1c23479833847cf04c3a7ece4928d670fce700d8 --output /tmp/taxonomy-tag-search-paired
```

The runner alternates baseline and candidate five times, records exact controller hashes, and restores the original source in `finally`. During this performance wave, all tests, analysis, profiling, and comparisons use the shared validation lane. Do not run another measurement concurrently.

The focused behavioral checks are `taxonomy_directory_test.dart`, `topic_list_filter_tags_test.dart`, `topic_filter_test.dart`, and `topic_filter_api_test.dart`. They passed 72 tests. Targeted analysis of the controller library and benchmark tests passed without issues.
