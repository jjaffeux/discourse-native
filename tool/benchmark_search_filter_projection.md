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
