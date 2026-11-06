# Category filter typing latency

The category filter used to await server search before projecting any locally
loaded matches. Its serialized lookup queue also made the current query wait
behind an obsolete query. The controller now publishes local category matches
immediately and enriches them through the existing server lookup queue.

The engine shares category matching, qualified ancestor paths, browsing, and
exact-category rows between local and enriched results. Current local matches
can be selected with Enter while the server is pending. Empty local results
still await remote discovery before keyboard fallback.

## Controlled latency measurement

The opt-in widget trace in `test/topic_list_filter_menu_ownership_test.dart`
opens the real Native topic-list category menu. It starts a held query, types
a child-category query, releases the old response at 2000 ms, and releases
the new response at 4000 ms. It checks the rendered child-category label
every 25 ms. Both responses and the final matching row are asserted.

| Revision | Trials | Median | Range |
| --- | --- | --- | --- |
| Before | 5 | 4025 ms | 4025 to 4025 ms |
| After | 5 | 25 ms | 25 to 25 ms |

The fix removes 4000 ms of simulated waiting in this scenario. The local
match appears on the first sampled frame after input, before either response.
The limiting factor before the fix was the two explicit response gates.

This test uses Flutter's virtual clock in the debug widget-test runtime.
It measures the dependency on server latency, not physical device frame
time, CPU throughput, or production network latency. Five trials per revision
were run in separate before/after batches. All returned the expected category,
made both expected server lookups, and reported zero failures. Clock drift
and machine load cannot change the simulated response-release schedule.

Run the trace from the repository root:

```sh
CATEGORY_FILTER_TRACE_OUTPUT=/tmp/category-filter-trace.json \
  flutter test --no-pub test/topic_list_filter_menu_ownership_test.dart \
  --plain-name 'category filter local result latency trace' --reporter expanded
```

Normal test runs skip the trace. The always-on regressions verify local
selection with pending requests under macOS, iOS, and Android layouts.

## Validation

The five directly related filter test files passed 93 checks. Two existing
failures reproduced identically with the unchanged controller from `6fb3561a4`.
The iOS named-filter test expects a count-only button label, and the tag menu's
feed-replacement test receives an empty search term after reopening. Both
remain outside this category-typing change. Static analysis of the changed
controller and test files reported no issues.
