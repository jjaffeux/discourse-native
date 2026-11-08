# Ten more verified performance improvements

Baseline: `44d621e91e052a783104c8ab22e855a3db74e2aa`.
Reviewed source: `62dc5579ac1c8b2da1d4f44783a361eda99f36e3`.

This batch adds ten improvements beyond the earlier batches on main. Nine have
measured elapsed-time gains. The other reuses a category-count snapshot instead
of rebuilding it. These results describe the operations and fixtures below.
They do not establish application FPS, rendering latency, or network gains.

## Nine complete-operation timing comparisons

Each value is milliseconds per batch, shown as median [minimum, maximum]. Six
balanced baseline/candidate pairs alternate which executable runs first. All
nine primary comparisons have non-overlapping ranges. All 348 timed workload
batches completed with their result checks passing.

| Operation and batch | Before ms | After ms | Less time |
| --- | ---: | ---: | ---: |
| Chat sidebar search, 300 queries over 30 retained messages | 108.326 [100.591, 111.894] | 5.694 [5.486, 5.973] | 94.7% |
| Alphabetical channel projection, 10,000 sorts of 100 channels | 470.984 [451.954, 488.495] | 304.783 [295.735, 309.864] | 35.3% |
| Activity append, retention and byte estimate, 2,000 operations on 300 rows | 224.982 [220.356, 231.848] | 175.244 [169.465, 186.065] | 22.1% |
| Draft deletion, 10,000 removals from nine 30-row packets | 94.850 [93.173, 100.159] | 64.478 [61.733, 65.630] | 32.0% |
| Same-poll empty ballot reconciliation, 100,000 calls with three options | 19.300 [18.805, 19.851] | 1.907 [1.727, 2.037] | 90.1% |
| Destination bookmark loading, 300 loads of 500 saved destinations | 638.205 [617.122, 656.048] | 477.906 [449.384, 510.422] | 25.1% |
| Emoji picker search, 300 ten-query sequences over 4,000 emoji | 330.299 [323.824, 335.991] | 239.277 [228.948, 246.967] | 27.6% |
| Mega-topic page publication, 300 loads with 20 retained removal stamps | 6.099 [5.860, 6.300] | 5.212 [4.921, 5.282] | 14.6% |
| Incoming feed merge, 1,000 merges of 30 arrivals into 300 retained rows | 157.326 [151.909, 160.865] | 103.269 [99.348, 109.370] | 34.4% |

Raw samples and all 29 primary/diagnostic workloads are in
[measurements.json](measurements.json).

## The tenth gain and independent work counts

Two alternating focused-test runs per side produced identical counts. These
checks call the actual APIs with counted model getters or retained object
identities. They add no instrumentation to application code.

| Actual API work | Before | After |
| --- | ---: | ---: |
| Distinct category-count maps returned by 100 reads over 300 tracked topics | 100 | 1 |
| Cooked-message reads during ten queries over 30 retained messages | 300 | 30 |
| Name reads while alphabetically projecting 100 channels | 1,636 | 100 |
| Category-name reads while estimating 300 activity rows | 300 | 1 |
| Category-name reads while appending to that activity feed | 333 | 1 |
| Unchanged row lists retained after deleting from nine packets | 0 | 8 |
| Option-list reads while reconciling an unchanged empty ballot | 2 | 0 |
| Name reads for a missing query over 4,000 emoji | 24,000 | 4,000 |

Category-count snapshot reuse is the tenth improvement. No elapsed-time claim
is made for it. [work-counts.json](work-counts.json) records both trials, exact
production revisions, and zero failed result checks.

## What each change does

1. `ChatController.sidebarConversations` retains extracted cooked text in a
   controller-owned weak identity cache. Immutable message replacements get
   fresh extraction; eviction does not leave a strong cache reference behind.
   Nullable results are cached too. Blank queries, excluded channels and deleted
   messages still skip extraction. Matching, missing, edited, raw, thread and
   author cases remain covered.
2. `TopicTrackingState` owns one lazy immutable category-count snapshot. Every
   topic mutation clears it before any early return. The reconciler forwards
   that snapshot and the shell retains its authenticated/snapshot-ready gates.
   Direct category IDs and category-definition topics keep their prior policy.
   Read/unread, moves, mutes, deletion, recovery and batch dismissals refresh
   values while old returned snapshots stay unchanged. Existing callers only
   read the result; immutability makes reuse safe.
3. Alphabetical chat-channel projections fold each name once into a temporary
   sort record. Starred channel grouping, ID ties, limits and active-channel
   retention remain intact. Priority and recency use their original paths.
4. Activity feed operations compute each category's byte charge once per call.
   Every row still pays that full charge. The temporary map is discarded after
   the operation, so replaced category data is recomputed. Direct map access
   avoids allocating a memoization callback per row. Fixtures use ordinary
   category fields without featured-topic amplification.
5. Account-feed deletion retains unchanged immutable packet row lists. Shifted
   cursors get new packets sharing those rows. Changed packets are filtered and
   copied. The outer packet list is still snapshotted, including absent-key
   deletions, because constructor input can be mutable. Draft order, duplicate
   removals, cursor shifts and input ownership remain checked.
6. Ballot reconciliation returns the existing draft for the same poll with an
   empty selection. A nonempty selection still checks current option IDs.
   This deliberately handles mutable option lists instead of assuming that
   a repeated poll identity makes its options immutable. Changed poll inputs
   continue through the original reconciliation rules.
7. Destination bookmark loading builds accepted-ID sets per site/account.
   It avoids searching the growing decoded list for each bookmark. First valid
   records, duplicate account groups, malformed entries and account boundaries
   retain their behavior. The sets are temporary. The 500-destination case is
   a scaling fixture; the 20-destination diagnostic has no measurable time gain.
8. Emoji search ranks prefix, alias and infix matches in one alphabetical pass.
   The catalog already has unique names. Tier priority, maximum results,
   aliases and catalog replacement remain checked. At most one result cap is
   collected per tier. No retained catalog search cache is added.
9. Topic page and gap publication query the existing live removal map by post
   ID. They avoid rebuilding the removal-delta set for every candidate post.
   The primary fixture retains 19 historical stamps and makes one removal
   during a 20-post request. It includes fixture creation and publication.
   Separate tests remove a returned post during network wait and synchronously
   during publication. This gain applies when removals occurred during a load;
   the zero-removal diagnostics show no measurable difference.
10. Incoming feed merges sort removed source rows once and use binary ranks to
    shift rows, checkpoints and viewport bounds. Strict and inclusive boundaries
    keep their original rules. A checkpoint-removal set is constructed once.
    The primary fixture alternates overlapping arrival groups at the normal
    300-row retention bound. The independent reference checks sparse retained
    rows as well as order and total row count.

## Cold-search cost and measurement limits

The chat text cache has a measured cold-path cost. For 300 operations that each
replace all 30 message bodies before searching, elapsed time rises from
**96.428 [90.154, 100.535] ms to 113.953 [105.949, 116.856] ms**, an 18.2% median
increase. That is about **0.058 ms extra per operation on this machine**. The
cache is kept for its large repeated-query saving. It also retains one extracted
string/nullable record per still-reachable message. No allocation-byte or
device-frame claim is made.

Other trade-offs are temporary sort records, ID sets and byte-estimate maps,
plus one category-count snapshot per tracking state. The small/cold diagnostics
are preserved even when their ranges overlap. Changed-poll reconciliation,
  small bookmark lists, new-only feed arrivals, zero-removal pages and fresh
  emoji-controller prefix searches do not have established timing gains.

The first cold-chat fixture wrote value-equal messages. `ChatMessage.merge`
retained those identities, so that row was warm and is **invalid as a cold
measurement**. Its source and [initial results](initial-measurements.json) are
kept as history. The corrected fixture changes every body and checks that the
store contains the new version. The first activity implementation removed
reads but did not improve time; the accepted version also removes per-row
callbacks. A later full run was disrupted by external tests and is retained as
[contended results](contended-measurements.json), not used for the table.
The frozen [focused comparison](focused-measurements.json) separately confirmed
activity gains at 30 and 300 rows before the final full comparison.

## Protocol and verification

- Apple M5 Pro, 18 logical CPUs, macOS 26.6, arm64, Flutter 3.47.7 and Dart 3.13.5.
- Both release runners use the same operation fixtures. Each action has ten
  untimed warmups, consumes its result and checks relevant values/order/counts.
  A mismatch throws; missing output, failed exits and inconsistent workload sets
  fail the collector. Six process pairs alternate AB/BA order.
- Fixed fixture construction is outside timing except where the complete load
  or cold/changed-input operation explicitly includes it. Network and persistence
  inputs are in-memory fakes. Actual owning API and controller code runs.
- This is a shared machine. Load rose above 22 on 18 CPUs during the discarded
  contended comparison. The final load reading was 11.82. All samples and ranges
  are retained. Overlap is not reported as an established gain.
- A separate baseline CPU sample found 805 main-thread samples under Dart AOT.
  These synchronous operations run on one isolate. Parsing, sorting, collection
  scans and allocations bound their work; unchanged result construction,
  validation and fake-response delivery limit the remaining savings. The native
  sample does not identify individual Dart methods and was excluded from timings.
  See [baseline-cpu-sample.txt.gz](baseline-cpu-sample.txt.gz).
- Verification passed **436 tests** in 21 explicitly selected
  directly related files. Focused analysis covers 19 Dart files. The full test
  suite was not run. [Focused test output](focused-tests.txt.gz),
  [analysis](analysis.txt), and [decision trail](decisions.tsv) preserve evidence.

The combined tree with main `118ecfd80`, tree
`7af93f73b0b90270234890d186eac1915dc5b40f`, also passed the same **436 tests**.
Main's concurrent changes are committed composer and handwriting work; no
performance production file overlaps. Independent source/evidence/integration
review by `gpt-6-astra` returned VERIFIED, including the disclosed cold-search
regression. See [integration output](integrated-tests.txt.gz) and
[source/binary provenance](provenance.json).

## Reproduce the comparisons

Run the three added proof files with `flutter test --no-pub`. To reproduce the
work-count comparison, create a disposable worktree at the stated baseline and
copy the three `test/perf_round_three_*_test.dart` files and three
`tool/perf_round_three_*_workloads.dart` files into the matching directories.
Copy `tool/benchmark_perf_round_three.dart` too for release measurements.
Run `flutter pub get --offline` in both checkouts, then:

```sh
python3 tool/prove_round_three_work.py /tmp/baseline /path/to/candidate /tmp/counts.json
```

The baseline flag relaxes work budgets and the newly introduced immutable
category-view assertion. Result values, ordering and existing ownership checks
still execute against both production versions.

Build each release executable with the identical runner and workload files:

```sh
FLUTTER_MACOS_ARM64_ONLY=true flutter build macos --release --no-pub \
  --target=tool/benchmark_perf_round_three.dart
```

Copy and ad-hoc sign each generated `Discourse.app` separately, then run:

```sh
python3 tool/compare_additional_improvements.py \
  /tmp/before.app/Contents/MacOS/Discourse \
  /tmp/after.app/Contents/MacOS/Discourse /tmp/results.json \
  --baseline-revision 44d621e91 --runs 6 --balanced-order
```

Add `--focused` to select activity and chat controls. The runner starts generated
fixtures and the Flutter binding, without opening the application shell or
reading account data, and exits after reporting checked results.
