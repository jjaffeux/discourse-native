# Rich chat scrolling

This investigation adds an offline reproduction containing 1,000 messages with
images, four reactions per message, onebox thumbnails, nested quotes, lists,
inline code and fenced Ruby. It found avoidable CSS parsing in newly mounted
rows and removes that work. It did **not** establish a repeatable improvement
in whole-frame scrolling time or eliminate intermittent native raster stalls.

## Reproduction and instrumentation

```sh
SCROLL_RICH=true SCROLL_EXIT=true flutter run --profile -d macos \
  -t tool/chat_scroll_profile_main.dart
```

The fixture uses the production channel, HTML renderer, image repository,
reaction controls and image decoding paths. Fake HTTP delivers a bundled
640×427 JPEG after 40 ms, with unique URLs and byte buffers for each image.
Reaction emoji use a local SVG stand-in. Message, quote and preview text varies
by message ID. No live server or external image host is involved.

Each process scrolls 360 steps of 40 logical pixels, 100 steps of 1,200 pixels,
and 100 steps back. The verified offsets are 0 → 14,400 → 134,400 → 14,400.
The 1,000-message default prevents hitting the history boundary during the fast
phase. `SCROLL_DM=true`, `SCROLL_WIDTH=360` and `SCROLL_DARK=true` select variants.
`SCROLL_START_DELAY=600` leaves time for manual inspection before recording.

The existing diagnostics capture records frame build/raster time, available VM
CPU stacks, row builds/layouts, viewport/day calculations and raster timeline
phases. The fixture adds phase boundaries, offsets, image-cache bytes, pending
image count and whether semantics is enabled. Reports and readable summaries
are written to the app's temporary directory; stdout prints their paths.

## Findings and change

There are zero whole-stream rebuilds while scrolling. Both versions mount
38/282/267 rows in the steady/fast/return phases. The usual day-extent scan is
about 15–35 microseconds. Those previously optimized paths are not the main
remaining work.

New rich rows still require HTML parsing/conversion, widget mounting, text
shaping/layout and allocation/GC. CPU samples contain these paths; stack
truncation and 1 ms sampling prevent assigning an exact percentage to each.
The measured row-layout work is roughly 95–106 ms across 100 fast steps.

One concrete waste is repeated custom CSS parsing. A fast pass makes 576
nonempty override requests, but they contain only four different strings:
link decoration and three paragraph-margin combinations. The app also used to
turn absent overrides into empty maps, invoking the CSS parser for unstyled
elements.

The HTML adapter now preserves absent overrides. The renderer skips empty
maps and uses its existing bounded, mutation-safe default-style cache for
custom overrides too. It still calls the builder for every element and keys
by its complete ordered output. Custom declarations retain their position
between default and inline CSS. Styles with unsupported compound expressions
keep the original parser path. No HTML, widgets, contexts or message contents
are cached. See the [vendor patch manifest](../../packages/flutter_widget_from_html_core/PATCHES.md).

A parsed-HTML cache experiment was discarded: its small apparent gain depended
on repeated nested text in an earlier fixture. The final fixture uses distinct
quote and preview content, and the final patch caches CSS syntax only.

## Native frame measurements

Two alternating baseline/fixed process pairs used Flutter 3.47.4 / Dart 3.13.3,
macOS 26.6.2, Apple M4 Pro, Skia/Metal and a 120 Hz display (8.33 ms budget).
The repository's Flutter pin was not changed. Baseline is the renderer at
`0cbb37d6` with the same final fixture/harness; fixed adds the CSS changes.
Both used the same native executable and enabled native accessibility.
CPU profiling was enabled with the Flutter desktop engine switches.

UI build p95, milliseconds:

| Phase | Baseline 1 | Fixed 1 | Baseline 2 | Fixed 2 |
| --- | ---: | ---: | ---: | ---: |
| Steady | 2.708 | 2.779 | 3.552 | 3.320 |
| Fast | 5.357 | 5.604 | 5.609 | 5.648 |
| Return | 6.225 | 5.924 | 5.828 | 5.922 |

There is no consistent whole-frame win in these pairs. Fast and return phases
had no UI or raster overruns. In pair 1, both versions had one steady UI
overrun and nine raster overruns; pair 2 had none. Earlier exploratory runs
also produced occasional UI overruns during fast scrolling.

Cold-image raster stalls varied substantially across launches. Captured slow
raster frames spent most of their time outside the recorded paint/preroll
markers. These measurements do not identify a specific app paint operation
responsible, and this patch does not claim to fix those stalls. Image loading
completed after each phase; pending count was zero. The return pass grew
Flutter's decoded-image cache to about 104.5 MB in both versions.

Full compact results, CPU samples, raster phase evidence and targeted CSS
measurements are in [rich-chat-scrolling.json](rich-chat-scrolling.json).

## Targeted CSS probe

The optional [instrumentation patch](rich-chat-css-probe.patch) times only
nonempty custom CSS parsing or cache lookup/copy. It accumulates stopwatch ticks
before converting to microseconds, including sub-microsecond cache hits.
It records input frequencies, not message HTML. Apply it only in an isolated
checkout, build the profile fixture, and run that same binary with
`SCROLL_CSS_CACHE=false` and `SCROLL_CSS_CACHE=true`. Remove it afterward; the
probe and parser bypass are not in shipping code.

One same-binary parser/cache pair measured these phase totals:

| Phase | Requests | Parser | Cache lookup and copies |
| --- | ---: | ---: | ---: |
| Steady | 81 | 1.700 ms | 0.133 ms |
| Fast | 576 | 3.005 ms | 0.170 ms |
| Return | 573 | 5.886 ms | 0.179 ms |

That is about 92–97% less time in this small targeted phase. It excludes
callback execution and map serialization. The absolute savings are only a few
milliseconds across an entire pass, consistent with the inconclusive frame
results above. These timings are not a 92–97% scrolling speedup.

## Native accessibility and interaction check

For these isolated profile bundles, a temporary native hook was placed after
assigning the Flutter view controller in `MainFlutterWindow.swift`:

```swift
if ProcessInfo.processInfo.environment["SCROLL_NATIVE_SEMANTICS"] == "true" {
  DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
    flutterViewController.engine.setValue(true, forKey: "semanticsEnabled")
  }
}
```

The hook was identical in both bundles and removed from source. Enable only
`SCROLL_NATIVE_SEMANTICS=true` with this hook. Enabling Dart semantics first
with `SCROLL_SEMANTICS=true` caused the later native bridge to miss the initial
tree; that invalid exploratory run was discarded. The accepted captures record
semantics enabled and have no AX-tree update errors. This ordering follows the
[Flutter macOS engine's bridge setup](https://api.flutter.dev/macos-embedder/_flutter_engine_8mm_source.html).

Native inspection covered 800-pixel light channels and 360-pixel dark DMs:
mouse scrolling through images, oneboxes and nested quotes; jump-to-latest
returning to message 1,000 and hiding the button; and a reaction changing from
12 to 11. Narrow desktop DM oneboxes wrap heavily inside the existing bubble
layout; that presentation is not changed here. No mobile-device run or live
network performance claim is made.

## Verification

The cache regression fails against the old parser path and passes with the
fix. It checks shared parsing with independent mutable declarations, changed
callback output for unchanged HTML, and reuse in a later body after mutation.
The existing cache tests cover capacity, declaration order/importance, complex
expression fallback and body-local fallback when the shared cache fills.

The initial focused run passed 257 tests and exposed a pre-existing site-identity
test that checked its API request before the profile route's Native popover
mounted. The same assertion failed with both renderer changes removed. That
fixture now waits for the opening frames to settle; all six source-site tests
then pass. No profile-navigation behavior was changed. Root static analysis,
formatting and all three vendor archive provenance checks pass.

Integration from main `9f7e9c3e` preserved the new cooked-details renderer and
passed all 261 focused tests, including details, cooked HTML/table/quote
rendering, selection, the four rich channel/DM scroll variants, chat lifecycle,
threads, uploads and reactors. Static analysis and the final macOS profile
build pass. Temporary probes and the native accessibility hook are absent from
the production source; the optional probe patch still applies cleanly.
