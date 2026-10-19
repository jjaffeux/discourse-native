# Giant HTML benchmark

Build `tool/benchmark_giant_html.dart` with `flutter build macos --profile --target tool/benchmark_giant_html.dart`, then run the built application's executable. The process prints one `GIANT_HTML_REPORT` JSON record and exits nonzero on a Flutter error, missing text, incorrect span order or incomplete layout.

The workload includes 20, 2,000 and 12,000 pairs of alternating bold and italic runs in one paragraph. It times parsing, DOM conversion, placeholder/span resolution and a subsequent mounted layout separately. This decomposition uses the vendored production builder directly, with no application custom-element callbacks. The resolved spans are checked against the complete expected text before mounting.

A second workload mounts the production `CookedHtml` with its automatic parsing threshold and `ProgressiveHtmlMode`. It includes an ordinary post, 1,600 paragraphs and a single paragraph with 24,000 styled runs. Completion uses the production loading and mounting notifications. Recorded wall time includes parsing and isolate transfer, conversion, frame scheduling, layout and paint. Final text inspection is subtracted. `uiFramesUs` records `drawFrame` work only. Async conversion can occur between frames, so this is not total UI-isolate time. Raster completion and display presentation are outside these measurements.

Run at least five alternating baseline/candidate processes built from the same surrounding revision and harness. Compare per-process medians and ranges, source/AOT hashes and recorded output counts. Exclude separate profiling runs from timing comparisons. The companion orchestration and raw evidence for the original comparison are in `/private/tmp/discourse-native-perf-wave2-01a15463/issue8`.

Set `GIANT_PROFILE=1` when launching with Dart CPU profiling enabled to collect separate CPU samples and post-mount heap counters. Heap counters cover the entire isolate after GC. Peak RSS is a process diagnostic, not the retained size of one post. These macOS profile results do not establish physical mobile performance or an FPS improvement.

The focused `test/giant_html_selection_test.dart` checks complete selection of one giant styled paragraph. Passing `--dart-define=GIANT_RENDER_OUTPUT=/absolute/output/directory` also writes light/dark parity captures with the macOS system font. Ordinary test runs do not load a platform font or write images.
