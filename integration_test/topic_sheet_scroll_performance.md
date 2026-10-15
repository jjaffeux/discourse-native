# Topic sheet scrolling

Measured on October 15, 2026, against `main` at `e2cf504fb`.

The reader's moving header clip repainted the enclosing sheet frame and
stationary floating artwork. Repaint boundaries around the reader, floating
date and progress control retain that artwork while preserving the live glass
backdrop layers. No material, scrolling, layout or gesture settings change.

The regression uses the real mobile shell, retained topic sheet, source list
and rich HTML replies. It warms the same replies, then moves down and back
over 80 frames while the header and dock animate. Counts exclude retained
repaint boundaries that Flutter merely composites.

| Platform / actual material | Paint callbacks before | After | Reduction |
| --- | ---: | ---: | ---: |
| iOS / Liquid Glass | 12,491 | 6,779 | 45.7% |
| Android / Standard | 9,367 | 5,830 | 37.8% |
| Android / Liquid Glass | 12,651 | 6,939 | 45.2% |

The sheet handle falls from 49 paints to at most one; the fixed date and
progress labels stay cached. Apple platforms resolve both saved material
choices to Liquid Glass, so the widget regression checks both saved choices
but the native timing benchmark measures each resolved material only once.

These counts establish less CPU paint work, not an FPS or raster-time gain.
Physical iPhone profiling at 1290 by 2796 pixels, 3x density and a reported
120 Hz identified additional raster cost in live glass. Shader batching,
filter composition, clip changes and fade removal did not provide a reliable
improvement and were discarded. The phone locked before the final physical
comparison; no physical-device frame-time improvement is claimed.

Validation includes 124 focused widget tests, four repaint regressions on a
native iPhone simulator, and the native frame-aligned timing harness. All 16
open/pulled sheet captures are byte-identical to unchanged main across light
and dark appearances, both saved materials and iOS/Android variants. Simulator
debug timings validate the harness and renderer, not physical-device speed.

```sh
flutter test test/topic_sheet_scroll_performance_test.dart
flutter test -d <simulator-id> integration_test/topic_sheet_scroll_paint_test.dart
flutter drive --profile -d <physical-device-id> \
  --driver integration_test/performance_driver.dart \
  --target integration_test/topic_sheet_scroll_performance_test.dart \
  --dart-define=PROFILE_LABEL=current
```

Keep the physical device unlocked for launch. The timing harness restores its
native viewport and pixel ratio, warms the replies, and drives each scroll
update on a native frame over three round trips. It reports build and raster
percentiles plus frames above 8.33 and 16.67 ms. `CAPTURE_TOPIC_SHEET=true`
adds native screenshots to the driver's response data after measurement.
