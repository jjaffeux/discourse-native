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

## Caret builds

`COMPOSER_ANALYSIS_CARET=true` measures `buildTextSpan` and selection-update-plus-build CPU time separately. It uses 6, 60, and 300 structured sections, plus a 60-section variant with mentions, hashtags, emoji shortcodes, and mixed-style keycaps. Each CPU case warms up for 20 operations and records 100 samples. `caretBuild` moves the caret through six prose offsets without changing source. `editBuild` inserts one letter before each build to check edit overhead. Theme style resolution, edit generation, and output validation occur outside the stopwatch.

The mode also mounts the actual `ComposerEditor` for each structured draft size and measures selection update through `endOfFrame`. The trace disables autofocus and excludes native text-input delivery. It retains one theme across fixtures to avoid theme-change animations during timed frames. That includes vsync, build, layout, and paint. It excludes keyboard delivery, raster completion, and physical display latency. The CPU cases build spans with a mounted theme but do not mount the editor. Do not treat their savings as a measured frame-rate improvement.

```sh
flutter run -d macos --profile --no-resident \
  --target tool/benchmark_composer_analysis.dart \
  --dart-define=COMPOSER_ANALYSIS_CARET=true
```

The CPU rows record source and painted-text checksums and reused span count. The mounted rows record rendered text, block output, frame count, and editor dimensions. Require equivalent outputs before comparing timings. Retain separate baseline and candidate bundles with identical harnesses, alternate at least five processes per side, and report the median and range of process medians.

Set `COMPOSER_CARET_DIAGNOSTICS=1` in the app process environment for a separate CPU profile of 10,000 selection updates and span builds. Enable Dart CPU sampling through the engine switches described above. Exclude that process from timing comparisons. The output lists sampled functions and distinguishes this diagnostic interval from measured rows.
