# Search HTML preparation benchmark

Build `tool/benchmark_search_html.dart` in macOS profile mode. Run the built application's executable and retain its `SEARCH_HTML_REPORT` JSON record. The process fails on Flutter errors, missing body text, or an incorrect number of highlighted characters.

The workload uses 20 paragraphs for an ordinary searched post, 400 paragraphs near the proposed worker threshold, and 1,800 paragraphs for a large searched post. Each paragraph contains three literal matches across plain, bold, and italic text. Each process performs one warmup and five measured repetitions per workload. A second mount reuses the same input. Ordinary input fits the existing shared cache; expanded large output exceeds its admission limit.

`legacyPreprocessUs` times the synchronous transformation helper on a distinct, equally shaped source so this probe does not prime the rendered body's cache. `uiFramesUs` measures `drawFrame` work. Its first entry includes the application build that previously ran highlighting synchronously. Engine DOM conversion can occur between frames, so summed frame time is not total UI-isolate CPU time. `eventLoopGapsUs` records a 1 ms heartbeat during preparation and mounting. These diagnostic gaps also include scheduling and output-inspection overhead. `endToEndUs` measures complete body mounting with text-inspection time subtracted. Raster completion and display presentation are outside these measurements.

Compare at least five alternating baseline and candidate processes built from identical harnesses and surrounding source. Check complete text, highlight counts, failure arrays, executable hashes, and revision provenance. Report per-process medians and their range. Keep ordinary cached cases alongside large cache misses. Moving preprocessing to a native worker can reduce synchronous frame work while increasing completion latency. Flutter compute does not provide a separate isolate on web, so native results establish no web gain.

This benchmark uses synthetic long posts on a desktop. It does not establish a mobile frame-rate improvement or a system-wide speedup. It retains the existing duplicate preprocessing and engine parsing. The separate giant HTML conversion work changes another phase of this same pipeline; their savings must not be added together.

## Measured result on 2026-10-25

Large searched posts have less synchronous work in their initial UI frame. Five alternating baseline/candidate macOS ARM64 profile processes produced 30 checked mount rows each, with zero failures. Each process used a warmup and five measured repetitions per case. Values below are medians of the five process medians; parentheses give their range in milliseconds.

| Case | Initial frame before | Initial frame after | Complete body before | Complete body after |
| --- | ---: | ---: | ---: | ---: |
| ordinary, first mount | 3.64 (2.85 to 5.08) | 4.66 (3.20 to 5.34) | 11.42 (10.74 to 12.19) | 12.46 (10.84 to 13.08) |
| medium, first mount | 5.10 (4.44 to 6.16) | 0.27 (0.25 to 0.36) | 149.40 (143.11 to 183.04) | 156.50 (144.34 to 166.72) |
| medium, repeat mount | 0.32 (0.28 to 0.40) | 0.38 (0.28 to 0.44) | 156.38 (140.90 to 189.43) | 148.81 (146.09 to 200.53) |
| large, first mount | 30.58 (25.55 to 39.42) | 0.54 (0.50 to 1.67) | 1496.76 (989.39 to 1548.80) | 1195.12 (883.79 to 1761.17) |
| large, repeat mount | 32.29 (26.74 to 36.31) | 0.51 (0.40 to 1.05) | 1398.14 (1032.34 to 1499.35) | 1281.55 (1015.05 to 1445.02) |

The large first-mount result removes about 30 ms of initial frame work. Its 25.55 to 39.42 ms baseline range and 0.50 to 1.67 ms candidate range do not overlap. The medium case also reduces initial frame work and supports retaining the 32 Ki code-unit threshold. Ordinary and admitted-cache cases have no demonstrated gain. Full-body completion ranges overlap broadly, so these runs establish no overall loading speedup or regression.

Later work still stalls the event loop. The large first-mount median maximum heartbeat gap was 136.17 ms before and 132.15 ms after, with overlapping ranges. The synchronous preprocessing probe and source path identify the removed initial-frame cost as HTML parsing, text-node rewriting, and serialization. Overall mounting remains limited by downstream rendering and frame scheduling. An excluded native sampling run captured Dart/Flutter CPU work, but its Dart AOT frames were not symbolicated to individual Dart functions.

The machine reported 18 processors and other work was active. Load averages before the alternating run were 10.01, 10.81, and 12.81. The end-to-end median movement exceeds the removed preparation phase and is not attributed to this patch. These measurements support the initial-frame claim only; they establish neither a physical-device FPS improvement nor a web gain.

The frozen baseline is `3dc07f6a9d6636204888e72e714e50e92ee003b9`. The candidate profile binary used the runtime patch subsequently committed as `1d2858250`, before behavior-neutral initializing-formal and brace fixes. The final branch was rebased separately and validated against current main. No engine change was included in these two profile artifacts; do not add this saving to the separate giant HTML conversion result.

The exact compiled harness snapshot and raw evidence are in `/private/tmp/discourse-native-performance-2026-10-25/search-html-highlighting/`. `measured-harness.dart` has SHA-256 `74fb85fb569814307712cba0be025f87297ee5676922c63ba2298f05dea22a66`; the committed harness differs only by braces required by analysis. `comparison.json`, the ten process JSON reports, `baseline-sample.txt`, build logs, and both copied profile applications retain the inputs and results. The baseline Dart AOT binary hash is `cb5e8d983e1433ea4c710dc9561c7a2c95ee8c58446575e98924567bdc282d4f`; the candidate hash is `384cc92f05c7ae5736c5573e52ac1435154e60a5b5b66c8459d6b40db30c63cd`.
