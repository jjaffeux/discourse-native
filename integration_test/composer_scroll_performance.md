# Composer scrolling profile

Run the real mobile composer with a synthetic 120-paragraph draft and fake
services. Each case warms the renderer, then repeats the same 1,800-pixel scroll
in both directions three times. Cases use keyboard insets of 0 and 336 logical
pixels. No forum account or network requests are needed.

Use a physical iPhone and profile mode for representative device timings:

```sh
flutter test integration_test/composer_scroll_performance_test.dart \
  --profile -d <device-id> --dart-define=PROFILE_LABEL=after
```

iOS simulators require debug mode. They can compare rendering changes on the
same host, but their timings do not establish performance on an iPhone:

```sh
caffeinate -is flutter test integration_test/composer_scroll_performance_test.dart \
  -d <simulator-id> --dart-define=PROFILE_LABEL=after
```

Compare the `COMPOSER_SCROLL_PROFILE` JSON records for each keyboard inset.
The test records build/raster percentiles and, in debug mode, backdrop-layer counts, excludes
frames outside the measured scroll window, and rejects captures interrupted
by long pauses. `total` is pipeline latency, including scheduling, so its
threshold counts must not be interpreted as dropped frames. Avoid other GPU
work during measurement and repeat the baseline and changed version.

## 2026-09-28 blur comparison

iPhone 18 Pro simulator, iOS 27, Impeller, debug mode, pixel ratio 3. Each
accepted capture contains 725–726 measured frames per keyboard state. The
physical iPhone was offline. Captures with long pauses were rejected.

| Keyboard inset | Raster mean, before | Raster mean, after | Raster p95, before | Raster p95, after |
| --- | ---: | ---: | ---: | ---: |
| 0 px | 3.87 ms | 3.01 ms | 4.76 ms | 3.61 ms |
| 336 px | 3.85 ms | 3.18 ms | 4.70 ms | 3.72 ms |

The composer now uses two Gaussian passes per edge instead of four. The
combined full-strength sigma stays at 12, and the keyboard plateau and gradient
remain. Composer backdrop layers drop from eight to four; including the sheet's
own backdrop, the scene drops from nine to five layers. This reduced p95 raster
time by 21–24% in this comparison. UI build means stayed below 0.8 ms in both
versions. These figures establish a simulator improvement; verify physical
iPhone frame budgets with the profile-mode command above.
