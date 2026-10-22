# Search filter preparation benchmark

Run in an isolated checkout with a baseline revision that predates the filter preparation cache.

```sh
python3 tool/benchmark_search_filter_projection.py \
  --baseline 1c23479833847cf04c3a7ece4928d670fce700d8 \
  --output /tmp/search-filter-timing
python3 tool/benchmark_search_filter_projection.py \
  --baseline 1c23479833847cf04c3a7ece4928d670fce700d8 \
  --counts --output /tmp/search-filter-counts
python3 tool/benchmark_search_filter_projection.py \
  --baseline 1c23479833847cf04c3a7ece4928d670fce700d8 \
  --profile --output /tmp/search-filter-profile
```

Use the shared validation lane when other performance sessions are active.

The driver extracts the baseline `availableFilters`, condition ordering, staging, hinting, and words getters into a temporary controller subclass. Both implementations retain the current production request lifecycle, query edits, panel, and fixture API. The scoped implementation changes only those preparation paths. Baseline and candidate controllers therefore run in the same Flutter process and alternate order across five measured rounds after warmup.

Forum, personal-message, chat, and restricted-capability cases include staged tokens, hints, and ordinary words. Each sample measures ten typing sequences through the controller, one real panel sequence, a 100-query plain-word control, and capability/locale replacement preparation. Cold panel opening is reported separately. Exact projection signatures compare available IDs/labels, ordered conditions, staged IDs/terms/operators, hints, and words. Rendered panel item keys and text are also compared outside the timed region.

`--counts` separately instruments core and message catalogue getter evaluations and whitespace query-tail parses. It restores the source files after execution. These counts describe source-level preparation work, not measured heap allocations. `--profile` captures baseline CPU samples separately from the timing run. Temporary probe tests are removed after each run.

The output contains raw samples, medians/ranges, source snapshots and hashes, load/core metadata, and logs. Timing uses Flutter's debug widget-test binding, including assertions and FakeGlass. It does not establish release typing latency, device frame rate, memory, battery, or network improvements. Network responses are fixture data. The current localization catalogue contains only English, so the French zone is a fallback control rather than a translated-label replacement.


## Recorded measurements on 2026-10-22

Baseline controller getters came from `1c23479833847cf04c3a7ece4928d670fce700d8`. The measured candidate was `b4ddd7c2e79d45428130c95b95fe08f13e251c80`, rebased onto local main `29e192a08130c5ceb88869f860228e1483c8b147`, including the search-row preparation change. Flutter 3.47.7 and Dart 3.13.5 ran on 18 cores. Initial load averages were 6.42, 9.20, and 14.08. Five alternating samples per side followed warmup. Exact controller and rendered panel comparisons passed with zero errors.

The accepted result is reduced preparation work. Over 120 forum query preparations, core catalogue getter evaluations fell from 4,920 to 1,760, message catalogue evaluations from 2,460 to 880, and whitespace query-tail parses from 1,050 to 110. Counts were identical in all five samples. Query submission parsing remains outside this cache and accounts for remaining catalogue construction.

Controller typing preparation in milliseconds per batch was:

| Case | Queries | Baseline median, range | Candidate median, range |
| --- | ---: | ---: | ---: |
| Forum | 120 | 673.1, 657.3 to 744.0 | 340.6, 334.4 to 350.1 |
| Messages | 80 | 222.2, 218.9 to 241.0 | 116.7, 116.2 to 140.5 |
| Chat | 80 | 220.7, 214.1 to 232.2 | 108.3, 105.1 to 147.1 |
| Restricted forum | 120 | 328.0, 322.3 to 355.3 | 146.8, 142.9 to 147.7 |

The small plain-query control and capability/locale preparation also improved in every case. Real panel sequence medians fell from 170.2 to 138.9 ms for forum, 66.5 to 54.6 ms for messages, 63.9 to 49.6 ms for chat, and 85.6 to 65.1 ms for restricted forum. Panel ranges overlap. Four of five forum and message pairs improved; all chat and restricted pairs improved. Treat these as corroborating debug measurements with uncertain magnitude. Default opening timings were inconclusive and show no reliable regression or improvement.

A separate baseline CPU profile contained 3,070 samples. `appL10n` appeared in 2,868 stacks and `globalSearchDefinitions` in 1,949. Repeated localized catalogue construction occupies the changed path. Filter availability checks remain dynamic and appeared in 991 stacks. This profile was excluded from timing results.

All 159 focused search tests passed after integrating the search-row owner, and targeted analysis found no issues. The candidate preserves live plugin schemas and condition-dependent operators. No result-row, request-lifecycle, UI-kit, or global cache API was changed.

The machine-readable summary is `tool/benchmark_search_filter_projection.json`. Raw timing, count, and CPU sample artifacts remain in `.audit/search-filter-projection/` in the issue worktree. These measurements establish reduced controller preparation work; they do not establish device typing latency or frame-rate improvement.
