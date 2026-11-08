# Ten measured performance improvements

Baseline: `f00de6dc2177ed4f0fc16e6e3ca5bf2ed6bcf487`.

The changes reduce CPU work and temporary allocations in ten existing app paths.
They do not change controls or add caches that outlive their owning model. The
measurements below cover the complete model operations described in each row,
including output validation. They are not application startup, frame-time, or
network latency measurements; no app-wide FPS improvement is claimed.

## Measurement protocol

- Apple M5 Pro, 18 logical CPUs, macOS 26.6; Flutter 3.47.7 / Dart 3.13.5.
- Two macOS arm64 **release** executables, built with the same
  `tool/benchmark_ten_improvements.dart` entry point and
  `tool/performance_improvement_workloads.dart` fixtures. The baseline uses the
  original production files; the optimized executable uses the changes in this
  commit. Both executables are ad-hoc signed local copies.
- Five alternating baseline/optimized process launches. Each synchronous workload
  has ten untimed warmups. Fixture creation is outside timing except for the
  explicitly cold tag-state construction and indexing workload. Each timed
  iteration consumes and checks its result; a mismatch throws and fails the run.
- Work counters additionally execute the actual model APIs against counted
  collections. They measure algorithmic work without timing noise or production
  instrumentation. The tests also check arbitrary unread removals, parser
  equivalence, qualification rules, ordering, immutable ownership, and updates.
- This is a shared development machine (load 5.06 on 18 logical CPUs when
  recording machine details). Alternation reduces drift, but small timing gaps
  should not be treated as established user-visible latency gains.
- These paths run synchronously on one Dart isolate. Their limits are collection
  scans, string normalization/regular expressions, object allocation, or an
  unchanged index construction, as specified below. GPU and network work are
  outside the measured region. A separate one-second native CPU sample, started
  two seconds after baseline launch and excluded from all timings, found all
  843 main-thread samples inside Dart AOT execution during the first unread-row
  workload. Native sampling does not resolve individual Dart function names;
  the counted collections identify the corresponding source-level scans.

## Fixture relevance

The feed controller normally retains at most 300 topic IDs. The 10,000-ID unread
fixture is deliberately a scaling stress case, **above normal app retention**;
its large timing percentage should not be read as typical scrolling latency.
At the normal 300-row bound with 270 hidden rows, the same actual API work counter
falls from 540 reads to 16 reads for both mappings. The separate 9,000-hidden-row
counter checks scaling. The 5,000-badge fixture likewise stresses repeated catalog
reads, not a typical forum's catalog size. Category counts represent a large
forum; account-feed rows and the 5,000 tracking rows fit the app's current limits.

## Results

All ten checked release workloads completed successfully: **zero result-check failures**. Each cell is the median and [minimum–maximum] milliseconds per batch, from five runs per version.

| Workload | Fixture/batch | Before ms | After ms | Less elapsed time |
| --- | --- | ---: | ---: | ---: |
| Unread row mapping | 100 × 1,000 row round trips; 9,000 hidden | 6161.704 [5969.415–6300.987] | 8.480 [7.641–10.233] | 99.9% |
| Hierarchical category suggestions | 100 complete suggestions; 1,000 categories | 258.247 [253.950–269.012] | 43.505 [40.867–44.815] | 83.2% |
| Hashtag reference matching | 100 × 1,000 comparisons | 7.435 [6.663–7.632] | 3.489 [3.171–3.537] | 53.1% |
| Badge catalog summaries | 10,000 total/earned/personal reads; 5,000 badges | 163.953 [161.682–167.685] | 0.053 [0.052–0.055] | >99.9% |
| Plain-text excerpts | 1,000 excerpt conversions; 30 repeated lines | 77.422 [76.183–80.030] | 68.736 [66.636–69.749] | 11.2% |
| Account page append | 1,000 appends; nine 30-row packets | 24.725 [24.135–24.863] | 17.630 [17.431–19.874] | 28.7% |
| Cold tag counts | 200 state constructions + indexing + two scopes; 5,000 topics | 125.759 [121.653–138.241] | 100.012 [98.488–101.067] | 20.5% |
| Sidebar category ordering | 100 hierarchy orderings; 1,000 shuffled categories | 48.919 [47.404–53.495] | 31.075 [30.980–31.623] | 36.5% |
| Emoji-free text | 1,000 scans; 1,000 backtick code spans | 1295.079 [1265.291–1303.812] | 391.381 [374.379–392.845] | 69.8% |
| Post-gap expansion | 1,000 reveals; 10,000 resident + 20 revealed posts | 508.936 [498.145–554.028] | 217.643 [214.493–219.573] | 57.2% |

The baseline and optimized ranges do not overlap for any workload. These are local model-operation measurements, not per-frame improvements. Badge numbers describe repeated reads **after** one lazy aggregate; they do not imply a comparable gain for first access.

Deterministic work budgets, measured separately against both implementations:

| Actual API work | Before | After |
| --- | ---: | ---: |
| Reads for both mappings over 270 hidden rows (normal 300-row bound) | 540 | 16 |
| Reads for both mappings over 9,000 hidden rows (stress) | 18,000 | 26 |
| Parent-ID reads for 1,000 root category suggestions | 1,001,000 | 2,000 |
| Candidate intersections for common + singleton tag | 5,000 | 1 |
| Name reads while sorting 1,000 distinct folded names | 24,828 | 1,000 |
| Resident-stream reads while revealing a 20-post gap (plus a duplicate response) | 230,000 | 30,000 |

An unchanged nine-packet append also retains all nine existing row lists and packets instead of reconstructing them. The ownership test verifies that subsequent input-list mutation cannot affect the retained snapshot. Plain excerpts avoid a DOM and selector queries; unqualified hashtag comparisons avoid two split lists; emoji-free input avoids backtick range materialization. Those allocation advantages follow directly from the exercised paths rather than inferred byte-size estimates.

Raw samples and operation counts: [measurements.json](measurements.json).

## What each change removes

1. **Unread row mapping** (`topic_feed.dart`): binary searches replace both linear
   walks over sorted hidden rows. This benefits scrolling, selection, and cursor
   mapping after many unread topics disappear. No index allocation is added.
2. **Hierarchical category suggestions** (`topic_filter_controller.dart`): one set
   of parent IDs replaces a full category scan for each candidate. Parent/up rows,
   category-only variants, and sorting keep their existing behavior.
3. **Hashtag reference matching** (`found_hashtag.dart`): separator positions
   replace two `split` lists per comparison. Case folding, type qualification,
   empty names, and malformed repeated separators retain the original rules.
4. **Badge catalog summaries** (`badge.dart`): one lazy aggregate over immutable
   groups replaces repeated scans for total, earned, and personal-state values.
   The cache lives only as long as that catalog; a replacement catalog recomputes.
5. **Plain excerpts** (`json.dart`): plain text skips DOM construction and CSS
   queries, preserving whitespace normalization. `<`, `&`, CR, and NUL still take
   the HTML parser path, retaining entities, emoji images, and tokenizer behavior.
6. **Account page append** (`account_feed_window.dart`): unchanged packets and
   their row lists are retained; overlapping updates copy only affected packets.
   Packets now snapshot their rows at construction, making reuse safe even when
   an input list is subsequently mutated. Cursor, eviction, and merge semantics
   remain covered by the account-feed retention tests. This adds one snapshot to
   manually constructed packets, in exchange for avoiding copies on later pages.
7. **Multi-tag activity counts** (`topic_tracking_state.dart`): intersections start
   from the smallest indexed tag bucket instead of the first requested tag.
   Missing tags return no candidates. Existing per-topic index and cached-count
   updates continue to apply. The cold workload includes the unchanged full index
   build, so its latency gain is smaller than the candidate-count reduction.
8. **Sidebar category ordering** (`category_sidebar.dart`): decorate/sort/undecorate
   normalizes each name once instead of during every comparison. Case-sensitive
   tie breaking, fixed positions, hierarchy, cycles, and duplicate IDs retain
   their ordering. Temporary sort-key records trade against repeated lowercase
   strings; they are released after sorting.
9. **Emoji-free text** (`site_emoji.dart`): discovery of backtick literal ranges is
   deferred until a valid-boundary shortcode is found. Text with no shortcode
   avoids the backtick match list and its width/next arrays. Actual emoji still
   respect escaped delimiters, inline code, and multiline fences.
10. **Post-gap expansion** (`post.dart`): one resident-ID set replaces repeated
    resident-stream membership scans. The set also suppresses duplicate revealed
    IDs. Consumed-prefix validation, insertion order, and remaining gaps retain
    their behavior. The set costs O(resident posts) temporary memory; the benefit
    is largest when expanding multiple posts in a long resident stream.

## Validation

- **320 tests passed** across 18 explicitly selected files covering unread feeds,
  topic filters and menus, category directories, badges and their page, JSON,
  account-feed retention, tracking updates, sidebar ordering, emoji, topic
  details, hashtag API boundaries, and composer identity resolution.
- Focused static analysis of all 14 changed/new Dart files: **no issues**.
- Release builds completed for both original and optimized production sources.
- The 12 new behavior/work-budget and workload tests passed. The measured
  collection budgets were also captured separately against the baseline.
- `dart format` and `git diff --check` passed. The full test suite was not run,
  in accordance with `AGENTS.md`.

The operation-budget checks can be repeated with:

```sh
flutter test --no-pub test/performance_improvements_test.dart
flutter test --no-pub test/performance_improvements_benchmark_test.dart
```

The second command provides diagnostic JIT timings only. The reported comparison
uses the release runner:

```sh
FLUTTER_MACOS_ARM64_ONLY=true flutter build macos --release --no-pub \
  --target=tool/benchmark_ten_improvements.dart
cp -R build/macos/Build/Products/Release/Discourse.app /tmp/native-perf-after.app
codesign --force --deep --sign - /tmp/native-perf-after.app
/tmp/native-perf-after.app/Contents/MacOS/Discourse
```

For a comparison, create a disposable worktree at the baseline revision, copy the
two `tool/*improvement*.dart` workload/entry-point files from this commit into its
`tool` directory, run `flutter pub get --offline`, build with the identical command,
and copy/sign its bundle separately. Alternate the baseline and optimized
executables five times. The runner uses generated in-memory fixtures, initializes
no application shell or accounts, prints checked workload times, and exits.
