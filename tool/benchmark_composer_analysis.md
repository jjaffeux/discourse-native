# Composer analysis benchmark

`benchmark_composer_analysis.dart` runs in Flutter profile mode. Its default mode measures Markdown analysis, structural indexing, controller updates, and mounted editor frames.

`COMPOSER_ANALYSIS_STRUCTURE=true` selects the synchronous controller workload. It uses 160-section plain and rich drafts. Rich drafts contain links, nested lists, tasks, code fences, quotes, galleries, standalone images, details, and tables.

```sh
flutter run -d macos --profile --no-resident \
  --target tool/benchmark_composer_analysis.dart \
  --dart-define=COMPOSER_ANALYSIS_STRUCTURE=true
```

Each of the eight cases warms up for 12 operations and records 100 individual samples. Cases cover insertion near the top and middle, distinct heading delimiter edits, and real history undo. The stopwatch includes the production controller setter or undo operation, structural index, gaps, and todo consumers. Edit generation, undo setup, checksums, and reference validation occur outside the stopwatch.

Every operation records an ordered SHA-256 digest of blocks, atoms, gaps, separators, syntax, list projection payloads and nested children, images, galleries, quotes, and todos. Each row also retains its final normalized output. Periodic checks compare against a fresh controller and structural parse. Any detected error makes the process exit unsuccessfully.

The final stdout JSON contains raw samples, output digests, counts, source sizes, runtime details, and separate diagnostic rows. `COMPOSER_ANALYSIS_OUTPUT` optionally writes that JSON to an absolute path fixed at build time.

For a comparison, retain separate baseline and candidate app bundles built with the same harness and flags. Alternate at least five processes per side. Require matching per-operation digests and final outputs before comparing per-process p50, p95, and p99. Record revisions, harness and AOT hashes, process statuses, and machine load. The p99 from 100 samples is a descriptive tail indicator.

Run CPU profiling in separate processes and exclude their timings from the comparison. On macOS, the engine accepts `FLUTTER_ENGINE_SWITCHES=1` and `FLUTTER_ENGINE_SWITCH_1=enable-dart-profiling=true`. Normal measured processes should have CPU sampling disabled. Diagnostic rows report whether samples were available.

The VM diagnostic interval includes operation preparation, result consumption, and service messages. Undo diagnostics also include two setup insertions per restoration. In Dart 3.13.5, allocation-profile accumulated counters alias current object-heap counters. Their deltas are heap snapshots, not total bytes or objects allocated per edit. Verify the runtime's counter semantics before making allocation claims.

The structural workload excludes keyboard and IME delivery, widget layout, rasterization, and display presentation. Its results describe desktop profile controller work and do not establish physical-device typing latency.
