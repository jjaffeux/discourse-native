# Mobile sidebar transitions

Sidebar button transitions use the existing 180 ms Native change timing with
an ease-out curve. The previous transition used the 300 ms tab timing.
Ordinary tab switches retain their existing timing, and swipes follow the finger.

The mobile shell retains dock controls while navigation progress moves their
wrapper. Navigation has its own `DScrollFootScope`, so the page dock's changing
fade no longer repaints sidebar lists. A repaint boundary retains the navigation
preview's artwork during its translation, scale, and opacity changes.

## Android measurements

The comparison uses baseline `a98216e24` and five alternating runs of each APK.
Each run warms four transitions, then measures six repetitions of each action.
All 240 measured transitions completed without errors.

The fixture uses the production mobile shell, 60 topics, its forum sidebar and chat
configuration, bundled fonts, and fake network data. The Android 16 ARM64 emulator
runs at 1080 by 2400 pixels, 2.625 density, and 60 Hz with host graphics.
Both APKs use Flutter 3.47.7 and Dart 3.13.5 in profile mode.
Per-widget tracing is disabled for these measurements.

The table gives the median of five run medians, with their minimum and maximum.

| Measurement | Baseline | Optimized |
| --- | --- | --- |
| Button open through all animation settling | 340 ms (333 to 348) | 224 ms (217 to 231) |
| Close action through all animation settling | 482 ms (481 to 489) | 381 ms (366 to 381) |
| Swipe-open UI frame build time | 3.19 ms (3.09 to 3.23) | 2.78 ms (2.63 to 2.93) |
| Swipe-close UI frame build time | 1.07 ms (1.02 to 1.07) | 0.57 ms (0.53 to 0.64) |

Open uses the header button. Close invokes the same shell action as Escape,
because the open sidebar hides that header. Settling includes auxiliary control
animations, so these elapsed times exceed the sidebar's 180 ms movement.
Swipe elapsed times remain about 399 ms open and 557 ms closed in both versions.

Deterministic widget instrumentation samples eight moving frames. Dock rebuilds
fall from eight to zero, and sidebar control paints fall from 488 to zero.
The regression checks pass on Android and iOS.

## Rendering limits

Flutter raster durations increase in several emulator scenarios despite the
reduced UI work. A diagnostic timeline retains only the final closing frames.
Those frames spend most raster time in `SurfaceFrame::Submit`.

A separate diagnostic run of each APK polls Android SurfaceFlinger presentation
timestamps. Median presentation intervals stay between 16.64 and 16.72 ms for
all four actions. Button transitions have no intervals above 25 ms in that run.
The swipe-close runs contain five baseline gaps and six optimized gaps above
25 ms. This single diagnostic comparison does not establish a smoothness gain.
The phase-duration budget counter in the JSON is not a dropped-frame count.

The host has 18 cores and also runs desktop processes and some focused widget
checks during the alternating trials. No physical Android device was available.
These results establish shorter button latency and reduced UI work on the
emulator. They do not establish physical-device GPU performance.

The [measurement data](data/mobile-sidebar.json) includes every run summary,
ranges, compiled-code hashes, and the presentation diagnostic.

## Reproduce

From `profiles/full`, run:

```sh
flutter drive --profile -d emulator-5554 --no-pub --no-dds \
  --driver ../../integration_test/performance_driver.dart \
  --target integration_test/mobile_sidebar_performance_test.dart
```

From the repository root, summarize the resulting report:

```sh
python3 tool/profile_mobile_sidebar.py \
  profiles/full/build/integration_response_data.json
```

For widget diagnostics, add
`--dart-define=PROFILE_SIDEBAR_WIDGETS=true` to the drive command.
The default VM trace buffer can retain only the end of a long recording.
The summary tool's `--trace` option reports whether the trace covers all samples.
Keep traced runs separate from timing comparisons.

The Android build uses the Rust toolchain declared by `libavif`. If a Homebrew
`rustc` shadows that toolchain, put the declared toolchain's `bin` first on `PATH`.

## Validation

Static analysis passes for both changed Dart files and the profiling and
regression tests. The focused suites pass 136 checks, including the six new
Android and iOS regression variants. Seven existing failures also reproduce
with both production files restored to baseline:

- The mode-switch drawer test cannot find the hidden header button on either platform.
- The iOS drawer capture test expects an offscreen chat row to be hit-testable.
- Four scroll-paint tests expect a title visibility change that does not occur.

The checks cover `mobile_drawer_structure_test.dart`, `d_history_transition_test.dart`,
`mobile_scroll_dock_test.dart`, `mobile_scroll_chrome_test.dart`,
`mobile_topic_history_transition_test.dart`, `mobile_scroll_performance_test.dart`,
and the mobile-shell cases for contextual actions, rapid root switches, parked
drafts, topic-action changes, site changes, and badge updates.
