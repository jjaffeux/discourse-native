# Desktop topic-row composition

This follow-up removes redundant composition in the existing Native components used by topic rows. The investigation starts at `87430a57a`; it does not modify the page-restoration scheduler or button-surface transform plumbing.

## Decision and diagnostic

The hypothesis is that removing proven redundant widget/layout owners and a dead fallback state lifecycle reduces row construction and traversal work without changing output or interactions. The acceptance checks are fewer mounted elements with matching content, directly related behavioral checks, and no demonstrated frame regression. A frame-time speedup requires five alternating native runs per version with non-overlapping p95 ranges; a smaller gap is inconclusive.

The native profile build uses the production topic-list workload from [fast desktop topic-list scrolling](fast-topic-list-scrolling.md): 3,000 topics, bounded retention, variable-height rows, events, assignments, category links, tags, and asynchronous page restoration. Timings use the same unmodified workload and disabled CPU sampling. Separate diagnostic runs enable CPU sampling or widget/layout tracing, never both.

The opt-in widget trace enables Flutter's per-widget build and per-render-object layout timeline events for wheel updates 61–64 in each phase. This short window keeps the complete nested timeline within the VM's finite buffer. The trace summarizer checks unmatched begins/ends and attributes both inclusive and self time. Inclusive costs overlap and must not be added together; these traced durations are diagnostic, not timing results.

The baseline fast-downward window contains 16,545 events with no unmatched boundaries. It constructs seven rows, 59 tooltip focus-ring wrappers, seven avatar fallbacks, and seven item-content groups. Text layout, construction during sliver layout, and teardown remain substantial. The chosen simplifications are:

- Fold the private tooltip focus-ring widget into its existing owner, retaining its decoration, focus owner, and exterior ring. Keeping that owner stable also preserves descendants when focusability changes.
- Use the existing `Column.spacing` layout in `DItemContent` instead of mounting separate spacer widgets, including zero-height ones in topic rows.
- Remove the single-child stack from explicitly sized avatars. Intrinsically sized avatar frames keep their loose layout.
- Make avatar fallback presentation stateless. Its removed delay API had left an always-true visibility assignment, unreachable timer branch, and empty update lifecycle.

No Native API or option is added. Link/context-menu, keyboard, hover, semantics, typography, touch-target ownership, account/site ownership, and retention rules continue through their existing components.

## Reproduction

All builds, tests, captures, and final merges are serialized through:

```sh
python3 /private/tmp/discourse-native-scroll-locked.py COMMAND [ARGS...]
```

Build each revision with this task's harness and preserve the complete bundle:

```sh
XCODE_XCCONFIG_FILE=/private/tmp/fast-topic-profile.xcconfig \
  flutter build macos --profile --no-pub \
  --target integration_test/topic_list_scroll_performance_test.dart
ditto build/macos/Build/Products/Profile/Discourse.app /private/tmp/discourse-row-composition/baseline.app
```

The temporary xcconfig disables signing and selects arm64 with `ONLY_ACTIVE_ARCH = YES`; repository signing configuration is unchanged.

Under the shared lock, capture diagnostics separately and hold the lock across the complete alternating comparison:

```sh
python3 tool/benchmark_topic_list_scroll.py \
  --baseline /private/tmp/discourse-row-composition/baseline.app \
  --widget-trace --output /private/tmp/discourse-row-composition/baseline-widgets
python3 tool/topic_list_widget_trace.py \
  /private/tmp/discourse-row-composition/baseline-widgets/widgets.json \
  --output /private/tmp/discourse-row-composition/baseline-widgets
python3 tool/benchmark_topic_list_scroll.py \
  --baseline /private/tmp/discourse-row-composition/baseline.app \
  --cpu --output /private/tmp/discourse-row-composition/baseline-cpu
caffeinate -di python3 tool/benchmark_topic_list_scroll.py \
  --baseline /private/tmp/discourse-row-composition/baseline.app \
  --candidate /private/tmp/discourse-row-composition/candidate.app \
  --output /private/tmp/discourse-row-composition/comparison
```

Repeat the diagnostic commands for the candidate. Local bundles and original logs are retained under `/private/tmp/discourse-row-composition/`.

## Structural results

The fast-downward diagnostic reaches the same topic and retains 15 row widgets on both versions. Mounted elements fall **11,563 → 11,377 (186 fewer, 1.6%)**. The complete [baseline census](data/topic-row-composition/baseline-widget-census.json) and [candidate census](data/topic-row-composition/candidate-widget-census.json) retain all phases.

| Fast-downward resource | Baseline | Candidate |
| --- | ---: | ---: |
| Mounted elements | 11,563 | 11,377 |
| Private tooltip focus-ring wrappers | 127 | 0 |
| Stack widgets | 87 | 72 |
| SizedBox widgets | 426 | 382 |
| Mounted avatar-fallback state objects | 15 | 0 |

The fallback element still exists as a stateless element. The state-object reduction follows the real mounted fallback count and its concrete widget type, rather than a change in element count. Ticker-capable state counts are unchanged.

The same four-update fast-downward trace window constructs seven rows and performs 82 paragraph layouts on each version. It removes 59 focus-ring wrapper builds, seven stack builds/layouts, and 20 spacer builds/layouts. The paragraph and intrinsic-measurement counts are unchanged. These observations demonstrate the removed work; they do not establish an elapsed-time speedup.

The [baseline trace summary](data/topic-row-composition/baseline-widget-summary.json) and [candidate trace summary](data/topic-row-composition/candidate-widget-summary.json) include synchronous counts, inclusive/self time, and the largest self-time paths. Both captures have zero unmatched begin/end events in all phases. Decompress the raw JSON into a Chrome trace viewer to inspect nesting:

- Fast downward: [baseline trace](data/topic-row-composition/baseline-fastDown.trace.json.gz), [candidate trace](data/topic-row-composition/candidate-fastDown.trace.json.gz).
- Fast upward: [baseline trace](data/topic-row-composition/baseline-fastUp.trace.json.gz), [candidate trace](data/topic-row-composition/candidate-fastUp.trace.json.gz).

The ordinary-downward endpoint falls 10,931 → 10,755 elements. The upward endpoint falls 11,595 → 11,407. Rendered endpoint titles match in both diagnostics. The remaining tree is still dominated by active controls, text, construction, and teardown.

## Frame timings

**Inconclusive in every phase.** Five alternating native runs per version complete without retries, failed workloads, or comparison errors. All p95 build-time ranges overlap. This change establishes a smaller tree and fewer build/layout/lifecycle operations. It does not establish faster frames or justify an end-to-end speedup percentage.

| Phase | Baseline build p95 median (range), ms | Candidate build p95 median (range), ms |
| --- | --- | --- |
| Ordinary downward | 2.414 (1.940–3.235) | 2.378 (1.235–2.888) |
| Fast downward | 6.485 (6.190–6.583) | 5.761 (5.057–6.591) |
| Fast upward | 4.146 (3.141–5.244) | 4.477 (3.389–4.805) |

Fast-downward frame total-span p95 medians are 7.890 → 7.931 ms, with overlapping ranges. Raster p95 medians are 0.732 → 0.726 ms. Text shaping, row mounting, and teardown on the UI thread remain the limiter. In the separate baseline CPU capture, layout includes 38.37% of fast-downward samples, widget inflation 32.96%, text-painter layout 9.62%, and unmounting 8.38%. Those inclusive paths overlap. The candidate's corresponding shares are 34.52%, 32.15%, 10.33%, and 9.24%. Single-run sample-share differences are not elapsed-time improvements.

The measured structural reduction is small relative to the whole tree. Neither the larger downward median reduction nor the upward median increase can be attributed reliably to this edit given the timing spread. The conservative result is to retain the focused, behavior-preserving deletions without claiming frame acceleration.

The machine has 18 CPU cores; load averages before the timing run were 2.47, 3.08, and 3.84. Desktop applications stayed open. Builds, Flutter tests, and the complete comparison command used the shared lock. The viewport is 1280 × 860 logical pixels at 2× density with native Metal Impeller. CPU sampling and widget tracing are disabled for all ten timing runs. Native timing captures disable semantics traversal; the focused widget tests validate accessibility. The workload uses synthetic topics/page latency and does not measure live-forum traffic, avatar downloads, or trackpad momentum.

All runs send the same 240 events per phase. Ordinary/downward endpoints reach topics 96 and 671. Upward endpoints reach topic 81 or 82, within the frozen two-topic and 5% distance tolerances as estimated row heights correct. The harness verifies actual rendered titles, substantial scrolling, viewport/density, retained feed count, and Flutter errors.

[Comparison data](data/topic-row-composition/comparison.json) includes every run and both framework hashes. The [baseline CPU table](data/topic-row-composition/baseline-cpu.txt) and [candidate CPU table](data/topic-row-composition/candidate-cpu.txt) retain all phases. Full collapsed stacks are retained for [baseline downward](data/topic-row-composition/baseline-fastDown.folded.gz), [candidate downward](data/topic-row-composition/candidate-fastDown.folded.gz), [baseline upward](data/topic-row-composition/baseline-fastUp.folded.gz), and [candidate upward](data/topic-row-composition/candidate-fastUp.folded.gz).

## Verification

The initial focused runs pass 231 existing tests across these files, including both light/dark topic-row goldens, exact inline hit bounds, pointer/keyboard activation, modified-link gestures, context menus, tooltip focus/hover/rings, avatar rings/RTL/scaling, and connected accessibility updates:

```sh
flutter test --no-pub \
  test/ui/d_avatar_test.dart \
  test/d_item_test.dart \
  test/d_tooltip_test.dart \
  test/ui_tooltip_test.dart \
  test/topic_card_components_test.dart \
  test/compact_topic_list_test.dart \
  test/topic_list_semantics_test.dart \
  test/full_width_topic_row_test.dart \
  test/open_link_test.dart
```

The added tooltip contract retains an input's local draft, focus node, active focus, and exact bounds while the hint is disabled/re-enabled. It passes on both the candidate and unchanged production files from `87430a57a`.

An exploratory version that toggles `focusable` instead of `disabled` fails on both versions with the same assertion: expected `Unsent draft`, actual empty text. Flutter Focus conditionally inserts its own semantics wrapper when `includeSemantics` changes. All three changed production files were restored to the actual base for that check. This existing focusability-transition issue is outside the composition change; the retained test covers tooltip availability instead. Original investigation logs remain under `/private/tmp/row-composition-focus-{baseline,candidate}.log`.

Targeted Dart analysis, Python compilation, and `git diff --check` pass. No full test suite is run.
