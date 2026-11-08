# Ten additional measured performance improvements

Baseline: `ecafcb48ae43157fc658ce839fdc40ee27ee0bec`.

These ten changes reduce work in existing app operations beyond the earlier
ten-improvement batch. Every primary comparison below has non-overlapping
baseline and candidate ranges across five alternating release runs. All 250
checked workload batches completed successfully. These are operation timings,
not measurements of application FPS, whole-page rendering, or internet latency.

## Results

Times are milliseconds per batch, shown as median [minimum, maximum]. The
percentage is the reduction in median elapsed time for that complete batch.

| Improvement and measured batch | Before ms | After ms | Less time |
| --- | ---: | ---: | ---: |
| Discovery selection, 1,000 selections from 30 sites | 13.615 [12.127, 15.283] | 4.604 [4.336, 4.878] | 66.2% |
| Image density selection, 30,000 selections from three candidates | 43.316 [42.568, 44.013] | 38.077 [37.424, 39.698] | 12.1% |
| Checklist state update plus fingerprint, 1,000 operations on 40 boxes | 513.149 [491.072, 528.646] | 137.062 [127.536, 145.387] | 73.3% |
| Theme decoding, 300 complete loads of 300 themes | 272.552 [270.382, 295.777] | 220.700 [216.355, 229.037] | 19.0% |
| Theme migration, 300 migrations with 300 held and 200 incoming themes | 790.037 [777.142, 921.731] | 487.377 [477.868, 515.983] | 38.3% |
| Tracking messages, 10,000 admission pairs with 1,000 active hints | 43.940 [43.366, 47.226] | 0.544 [0.494, 0.568] | 98.8% |
| Tag-page filtering, 1,000 complete filters of 1,000 tag names | 1103.194 [1086.553, 1224.456] | 94.845 [90.207, 100.602] | 91.4% |
| Shared GET coordinator, 10,000 complete joined request round trips | 37.486 [36.712, 39.758] | 30.781 [30.563, 32.506] | 17.9% |
| Nested replies, 200 complete loads of twenty overlapping 30-reply pages | 104.708 [99.926, 121.201] | 37.931 [37.566, 39.783] | 63.8% |
| Tag directory, 300 complete API loads of 1,001 tags | 210.647 [205.254, 235.064] | 167.228 [162.972, 187.573] | 20.6% |

Raw runs and every diagnostic: [measurements.json](measurements.json).

## What changed and what stays bounded

1. `DiscoverSite.suggestions` now stops after the tenth eligible distinct site.
   It previously normalized every site URL before truncating the result.
   Invalid sites, already-added identities, subfolders, duplicate order, and
   fixed-length result lists retain their behavior. A counted actual API call
   with excluded entries reads **104 sites before and 13 after**.
2. `srcsetCandidate` finds the smallest covering density and largest fallback in
   one pass. It avoids the sorted key list. Parsing, density tolerance,
   first-candidate duplicates, width-descriptor fallback, empty sources and
   nonfinite device ratios retain their behavior. Three candidates match the
   normal responsive-image shape; thirty candidates are a separate stress test.
3. `PostChecklistDocument.withStates` and `fingerprint` deep-clone their parsed
   DOM. They avoid serializing and reparsing that tree. The return value is still
   serialized, and target discovery still runs. Ownership, permanent boxes,
   quote exclusions, entities, malformed tables, templates, SVG and unclosed
   markup are checked against literal and reparsed reference results.
4. Theme decoding uses a temporary set of successfully accepted IDs. It avoids
   searching the growing decoded library for each input theme. Invalid-first,
   valid-later duplicates still work because failed parses never reserve an ID.
   The set adds O(n) temporary storage. The 300-theme measurement describes a
   large library; the ten-theme diagnostic shows **no measurable difference**.
5. Theme migration builds a temporary first-wins ID index. It avoids repeated
   library scans for existing identities and suffix collisions. Duplicate IDs,
   identical themes, ordering, selected-ID remapping and idempotence are checked.
   It skips indexing when the incoming legacy library is empty. That common
   empty case shows **no measurable difference**. The main fixture is a scaling
   test of large saved libraries, not a typical new-account migration.
6. Tracking-message filtering records the earliest pending hint expiry. Ordinary
   messages compare that deadline instead of sweeping both maps. Exact-boundary
   expiry, refreshes, clock reversals, muted precedence and the existing capacity
   cap retain their behavior. The actual API counter falls from **100,000 to
   100 expiry comparisons** for 100 messages with 1,000 unexpired hints.
7. Tag matching retains one normalized query of at most 4,096 UTF-16 code units.
   A different query replaces it; longer input clears retention. Cached words
   stay private, and matching copies them before removing found words. The
   app's owning caller filters one short tag name at a time. The complete
   filtering benchmark changes its query every batch and includes the first
   cold parse, all 1,000 row checks, result construction and validation. Separate
   matching/missing one- and two-word diagnostics also improve. Multiple fields
   are normalized at most once, reducing counted field reads **60 to 10** in
   the separate scaling fixture. Other pages can evict the one-entry cache;
   that affects reuse, not results. No query history is accumulated.
8. Immutable GET request keys compute their hash once. URL, header snapshot,
   timeout, byte limit and session/authentication identities already stay fixed.
   The actual map-operation check reduces URI hash evaluations **102 to 1**.
   Each key adds one lazy integer. The primary measurement creates a cold key,
   joins two actual coordinator callers, performs one fake send and validates
   both delivered responses. The separate key-map microbenchmark improves
   39.2%; real network transport is outside both measurements.
9. Nested reply merges seed one temporary membership set per nonempty incoming
   list instead of searching the growing destination for every ID. The set is
   discarded after the merge. Stable first-seen order, duplicates within and
   between pages, terminal pagination and all 600 loaded replies are checked.
   The one-child diagnostic shows **no measurable difference**. The main gain
   applies to larger loaded reply lists and multiple arrivals per page.
10. Tag directory sorting computes each folded name once. It avoids repeating
    Unicode lowercasing inside the comparator. Temporary sort-key records add
    O(n) storage. The measured API operation includes fake HTTP response
    handling, JSON decoding, deduplication, sorting, immutable output construction
    and validation. Case-sensitive tie-breaking and first-record ownership stay
    intact. Actual HTTP latency and the tag-page widget build are outside it.

## Measurement protocol and limits

- Apple M5 Pro, 18 logical CPUs, macOS 26.6, arm64; Flutter 3.47.7 / Dart 3.13.5.
- Both macOS release executables use byte-identical workload files and the same
  runner. Baseline production code comes from the stated revision. Each bundle
  is copied and ad-hoc signed separately before execution.
- Five process launches per side alternate baseline/candidate. Each workload has
  ten untimed warmups, or twenty for discovery/image selection. Construction of
  fixed fixture inputs is outside timing; cold query parsing per tag-filter
  batch, theme decoding/migration, cold GET keys, controller loads and API output
  processing are inside their respective timed operations.
- Every timed action consumes and checks its result. A wrong count, identity,
  order, status, body or output throws. The comparison runner rejects nonzero
  exits, missing results, inconsistent workload sets and invalid timings.
- This is a shared development machine. Builds and tests finished before timing.
  Load average after the final comparison was 9.94 on 18 logical CPUs. Alternating
  order and reporting ranges reduce, but cannot eliminate, environmental noise.
  Overlapping ranges are reported as no measurable difference.
- A separate one-second native CPU sample, started two seconds after baseline
  launch and excluded from every timing, found all 819 main-thread samples in
  Dart AOT execution. These operations run on one isolate. The removed limits
  are URL normalization, sorting, HTML tokenization, repeated collection scans,
  query parsing and hashing. Unchanged parsing, allocation, result checks and
  future delivery limit the remaining gains. The native sample does not resolve
  individual Dart function names; the source and counted API checks identify
  the removed work. See [baseline-cpu-sample.txt.gz](baseline-cpu-sample.txt.gz).
- Discovery's API caps the incoming catalog at 50 sites, so the primary 30-site
  fixture fits production. Its 300-site diagnostic is stress only. Large theme
  libraries, 600 nested replies and 1,000 hints test scaling; their percentages
  do not describe small catalogs or the ordinary cost of a single bus message.

The first search implementation improved only a large multi-field fixture. It
was revised after real short-tag measurements showed no gain. The preserved
[initial measurements](initial-measurements.json) and
[decision trail](decisions.tsv) record that rejected claim. The final long-field
diagnostic has overlapping ranges and is not counted as an established win.

## Verification and reproduction

**454 tests passed** in fourteen explicitly selected directly related files.
Focused analysis of all seventeen changed/new Dart files found no issues; the
revised search files were analyzed again. Formatting and `git diff --check`
passed. The full test suite was not run, following `AGENTS.md`.

[Focused test output](focused-tests.txt.gz) and
[baseline work-counter output](baseline-tests.txt.gz) preserve the evidence.
Independent review inspected the owning callers, source invariants, normal-size
diagnostics, cache bounds and final release measurements.

Main advanced concurrently to `5118a7465` before landing. The conflict-free
combined tree `5c3bae4b78bfdbd48626bc866848ba86d6145794` passed **455 tests** in
the same fourteen files and focused analysis of the overlapping API and search
files. Independent integration review verified that the category-search change
and tag sort occupy separate methods and that shared authentication still
replaces immutable request identities. See [integrated tests](integrated-tests.txt.gz)
and [integrated analysis](integrated-analysis.txt). Release numbers above remain
the controlled baseline-versus-performance-branch comparison.

Run the added behavior/work-budget checks with:

```sh
flutter test --no-pub test/additional_model_performance_test.dart \
  test/additional_selection_performance_test.dart \
  test/additional_service_performance_test.dart
```

Build the optimized runner from this commit:

```sh
FLUTTER_MACOS_ARM64_ONLY=true flutter build macos --release --no-pub \
  --target=tool/benchmark_additional_improvements.dart
cp -R build/macos/Build/Products/Release/Discourse.app /tmp/additional-after.app
codesign --force --deep --sign - /tmp/additional-after.app
```

Create a disposable baseline worktree at the stated revision. Copy
`tool/benchmark_additional_improvements.dart` and all three
`tool/additional_*_performance_workloads.dart` files from this commit into its
`tool` directory. Run `flutter pub get --offline`, build using the identical
command, and copy/sign that bundle as `/tmp/additional-before.app`. Then run:

```sh
python3 tool/compare_additional_improvements.py \
  /tmp/additional-before.app/Contents/MacOS/Discourse \
  /tmp/additional-after.app/Contents/MacOS/Discourse /tmp/additional-results.json
```

The runner initializes the Flutter binding and generated in-memory fixtures,
without starting the app shell, accounts or a real network connection. It exits
after reporting the checked results. `PERF_BASELINE=true` relaxes only work-budget
assertions in the added tests; output and ownership assertions remain active.
