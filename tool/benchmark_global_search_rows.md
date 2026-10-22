# Global search row preparation

This probe counts work in production `GlobalSearchPanel` interactions. It loads
one or thirty pages of thirty forum results, presses ArrowDown ten times, opens
the selected result, then reveals and opens the final offscreen result. Each
workload runs five times. It checks result identity, visible selection and Flutter
errors. The panel is 432 by 300 logical pixels with normal text scaling.

Baseline is local main `1c23479833847cf04c3a7ece4928d670fce700d8`. Both sides use
Flutter 3.47.7 and Dart 3.13.5. All five operation-count samples were identical on
each side. The JSON records the samples. Missing counter keys mean zero.

| Loaded results | Work counted | Baseline factories | Candidate factories | Baseline keyboard callbacks | Candidate keyboard callbacks |
| --- | --- | ---: | ---: | ---: | ---: |
| 30 | Page arrivals | 30 | 9 | 30 | 30 |
| 30 | Ten selections | 300 | 111 | 300 | 0 |
| 30 | Selections plus final reveal | 330 | 140 | 330 | 0 |
| 900 | Page arrivals | 13,950 | 270 | 13,950 | 900 |
| 900 | Ten selections | 9,000 | 111 | 9,000 | 0 |
| 900 | Selections plus final reveal | 9,900 | 1,010 | 9,900 | 0 |

Selections plus final reveal includes the ten selections. The complete 900-result
workload, including page arrivals and cache population, constructs 23,850 versus
1,280 result widget graphs and creates 23,850 versus 900 keyboard-open callbacks.
Both versions have five mounted result rows at the selection checkpoint.

These are deterministic work counts from debug widget tests. They establish less
widget and callback preparation in actual panel interactions. They do not
measure allocation bytes, physical-device latency, frame rate, heat or battery.
The panel still scans loaded results and recreates action records on selection.
The remaining widget construction follows viewport demand, including offscreen
reveal. No constant-time selection or fewer-mounted-rows claim is made. Debug
stopwatch readings in the original local logs are not used as performance evidence.

Run from an isolated checkout with dependencies resolved. The script temporarily
instruments the panel and its fixture and restores both in `finally`. Serialize
it with the repository's shared validation lane. For example:

```sh
python3 /Users/joffreyjaffeux/Code/discourse-native/.audit/perf-wave-20261022/run_lane.py validation -- python3 tool/benchmark_global_search_rows.py /private/tmp/search-rows-baseline.log --revision 1c23479833847cf04c3a7ece4928d670fce700d8
python3 /Users/joffreyjaffeux/Code/discourse-native/.audit/perf-wave-20261022/run_lane.py validation -- python3 tool/benchmark_global_search_rows.py /private/tmp/search-rows-candidate.log
```

Behavior validation runs only `test/global_search_panel_test.dart`,
`test/global_search_controller_test.dart` and `test/global_search_progressive_test.dart`.
The 95 passing cases include progressive metadata/target replacement, category
checklist keyboard selection, filter navigation, pagination, and offscreen result
wrap/reveal at normal and doubled text scaling. Targeted analysis is clean.
