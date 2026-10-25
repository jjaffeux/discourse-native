> Historical measurements for the retired rendering. The current app uses the [flat appearance](../docs/material-mockup-parity.md).

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

Physical iPhone comparison completed in profile mode at 1290 by 2796 pixels,
3x density and a reported 120 Hz, with actual Liquid Glass. Each capture warms
one round trip, then records three frame-aligned round trips over 12 seconds.
The sequence alternates unchanged `e2cf504fb` and fixed `3ef4fa104`, reusing
the same two compiled app bundles for repeats. The final pair each followed
at least 60 seconds idle.

| Capture | Frames | Build mean ms | Raster mean ms | Raster p95 ms | Raster frames above 16.67 ms |
| --- | ---: | ---: | ---: | ---: | ---: |
| Baseline 1 | 773 | 0.750 | 15.029 | 24.434 | 351 |
| Fixed 1 | 1,379 | 0.457 | 5.416 | 9.933 | 0 |
| Baseline 2 | 950 | 0.600 | 11.946 | 19.267 | 207 |
| Fixed 2 | 685 | 0.848 | 17.058 | 28.787 | 416 |
| Baseline after idle | 679 | 0.906 | 17.029 | 28.525 | 441 |
| Fixed after idle | 718 | 0.780 | 15.312 | 33.562 | 318 |

All six runs passed the workload assertions. The initially fast fixed capture
did not repeat; the idle interval did not stabilize timings. These captures
do not establish a reproducible physical-device frame-time improvement.
Device thermal and power states were not recorded, so the timing variation
cannot be attributed to a particular cause. Frame counts are timing samples
within the measurement window, not an independent display FPS measurement.

Raster cost remains substantially higher than build cost with live glass.
Shader batching, filter composition, clip changes and fade removal did not
provide a reliable improvement and were discarded. The shipped change
reduces the verified repaint work while preserving the existing appearance;
the remaining live-glass raster bottleneck is unresolved.

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
