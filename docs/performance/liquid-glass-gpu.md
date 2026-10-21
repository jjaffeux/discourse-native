# Liquid Glass GPU budget

Investigated on October 21, 2026, against `main` at `7ab351f43`, on a physical
iPhone 15 Pro Max (iOS 26.6.2, 1290 by 2796 pixels, 120 Hz) with profile
builds, plus the iPhone 17 simulator for quick checks.

The phone grew hot after a few minutes of scrolling or chatting, and frame
rates fell. The same happened with `liquid_glass_easy` before the switch to
`liquid_glass_renderer`. Two causes are fixed here: a focused text field drew
120 frames per second while nothing moved, and the reading panel's edge
highlight ran a full-panel blur on every frame. The remaining cost is the live
glass itself, mostly the dock; the options are listed at the end.

## Measuring

`integration_test/glass_gpu_budget_test.dart` holds each phone screen (topic
list, topic reader, chat) idle and scrolling for fixed windows, with glass and
again under high contrast, which resolves every Native surface to its opaque
fill. Each window reports the frames the app requested, the frames drawn, and
`FrameTiming` build and raster times, plus its device wall-clock bounds.

`tool/glass_gpu_windows.py` reads an Instruments Metal System Trace recorded
during the run and reports the app's GPU busy time in each window. Four things
make the simpler numbers misleading:

- `FrameTiming` raster time is raster-thread time. Metal runs the GPU work
  asynchronously, so on the topic list the raster thread reported 266 ms per
  second while the GPU was busy 789 ms per second. Only the trace measures
  what heats the phone.
- The live integration binding schedules another engine frame after every
  frame it did not pump (`LiveTestWidgetsFlutterBinding.handleDrawFrame`), so
  one caret blink keeps an idle screen drawing. The harness counts a frame as
  requested when `hasScheduledFrame` is set at `onBeginFrame`, which is what
  `WidgetsFlutterBinding` draws in the app.
- The phone heats up during the runs themselves, from Nominal to Serious within
  a few minutes, and throttled clocks inflate GPU time. Unchanged code measured
  789, then 829 ms per second, in two runs. Compare variants only when they are
  interleaved in one run, switching every few seconds.
- The simulator renders on the Mac's GPU. It predicted gains for several
  changes that the phone did not show, and missed the edge highlight's cost.

## What glass costs on the phone

`7ab351f43`, 120 Hz, GPU busy time while scrolling:

| Screen | Glass | High contrast |
| --- | ---: | ---: |
| Topic list | 789 ms/s | 352 ms/s |
| Topic reader | 842 ms/s | 389 ms/s |
| Chat | 849 ms/s | 389 ms/s |

One topic-list frame with glass, GPU milliseconds by pass:

| Pass | Glass | High contrast |
| --- | ---: | ---: |
| Render passes | 3.86 (9.3 per frame) | 1.88 (1.2 per frame) |
| Gaussian blur | 1.28 (10.5 per frame) | none |
| Root backdrop copy | 0.81 | none |
| Total | 7.35 | 3.72 |

The topic list's only live glass is the dock: its capsule, two pills and the
capture that lets the pills refract the capsule. On Impeller, each backdrop
read ends the current render pass, starts a new one and redraws the previous
texture. Impeller has no raster cache, so every static decoration that uses a
mask blur also reruns its blur on every frame.

## Focused text fields

Every settled screen requested no frames except while a text field had focus.
Material `TextField` turns on `cursorOpacityAnimates` on iOS; the caret then
runs `_DiscreteKeyFrameSimulation.iOSBlinkingCaret`, which changes opacity 8
times per second but ticks on every vsync. `DInputOTP` drew its own caret with
a repeating fade.

The kit now passes `cursorOpacityAnimates: DControlStyle.caretOpacityAnimates`
(false) to every `TextField`, and the OTP caret blinks on a timer. Carets blink
on and off each half second instead of fading.

| Chat, composer focused, idle | Requested frames | GPU busy |
| --- | ---: | ---: |
| `7ab351f43` | 119.9/s | 657 ms/s |
| Fixed | 2.0/s | about 10 ms/s |

The fixed GPU figure is 2 frames times the 5 ms each costs; the harness itself
keeps drawing because of the binding chain above.
`test/focused_text_field_frame_rate_test.dart` pins the request rate for every
kit text field.

## Panel edge highlight

In glass mode, `_PanelEdge` draws the panel's inset `0 1px 1px` highlight as
the outside of the panel shape shifted down 1px, blurred with
`MaskFilter.blur`. That path was the whole panel inflated by 8px, so Impeller
blurred the entire panel on every frame. High contrast uses `_DepthEdge`
instead, which has no blur.

The same outside is now drawn as four disjoint bands along the edges: the top
and bottom bands cover the corner radii, and the side strips are 12px wide.
Each blur covers its band's bounds. Rendered side by side with the previous
painter, pixels differ by at most 5 of 255 at 3x density, 2 to 3 in dark
mode and 13 at 1x, all within 1 point of the side edges, under the rim
stroke.

Interleaved on the phone, topic-list scroll:

| Run | `7ab351f43` | Edge bands | High contrast |
| --- | ---: | ---: | ---: |
| 1, GPU busy | 790 ms/s | 695 ms/s | 371 ms/s |
| 2, GPU busy | 793 ms/s | 688 ms/s | 361 ms/s |

In run 1, with the phone at Serious thermal state, chat scrolled at 75.5
frames per second unchanged and 119.7 with the bands.

## Measured and rejected

| Change | Result on the phone | Notes |
| --- | --- | --- |
| Pills drawn without reading the backdrop, no dock capture | Reader and chat fell from 109-120 to 70-83 fps | Simulator showed 37% less raster time |
| Live pills with frost 0 | Same fall as above | |
| One capture per control row in panels | Not run on the phone | Simulator: pixel-identical, no measurable change; copies got smaller but no fewer |
| One shared backdrop key per panel | Breaks `scroll_glass_backdrop_test` | The progress pill shows scrolled rows through its backing |
| Independent reads, no panel `saveLayer` | Breaks `mobile_settings_panel_clip_test` | A card fill runs 4px into a rounded corner |
| Panel clip without `saveLayer` | 692 against 688 ms/s with edge bands | No gain |
| `liquid_glass_widgets` 1.14.0, standard and minimal | 11.5 to 15.5 ms GPU per frame against 8.3 to 12 | Same backdrop reads, other shaders |
| Native `UIGlassEffect` dock as a platform view | About the same GPU per frame | Flutter splits the frame around the view |
| 60 Hz cap | Not adopted | Halves frames; the product keeps 120 Hz |

## A native tab bar

A prototype drew the dock's glass as a `UIGlassEffect` view added above the
Flutter view in UIKit, not inside Flutter's frame, with the dock drawing no
glass of its own. Interleaved on the phone:

| Screen | `7ab351f43` app GPU | Native glass app GPU | Render server |
| --- | ---: | ---: | ---: |
| Topic list | 804 ms/s | 638 ms/s | +24 ms/s |
| Topic reader | 842 ms/s | 682 ms/s | +15 ms/s |

With the edge bands as well, the topic list measured 561 ms/s against 790,
and the render server 68 against 19. In the prototype the icons sat under
the native glass. Shipping it means drawing the dock's items natively, as
iOS 26 `UITabBar` does, and driving selection, badges and the fold over a
channel.

## Open costs

- The dock's fold puts a fractional `Opacity` above live glass. The package
  seeds that opacity with a second backdrop read (`_OpacitySeedLayer`), and the
  reader and chat drop frames while the dock folds during a scroll.
- With the dock's glass and the edge blur gone, the topic list still measured
  561 ms/s against 361 under high contrast. Glass mode also adds translucent
  panels, three anti-aliased clips and the panel `saveLayer`; the last one
  measured no cost.

## Reproducing

```sh
flutter test test/focused_text_field_frame_rate_test.dart
flutter drive --profile -d <physical-device-id> \
  --driver integration_test/performance_driver.dart \
  --target integration_test/glass_gpu_budget_test.dart \
  --dart-define=PROFILE_LABEL=current > run.log &
xcrun xctrace record --template 'Metal System Trace' \
  --device <physical-device-id> --all-processes --time-limit 90s \
  --output run.trace
python3 tool/glass_gpu_windows.py run.trace run.log
```

Start the recording once the log shows "Installing and launching". Keep each
recording under about 100 seconds and stop it before the app exits. Longer
recordings and recordings cut by the app's exit came back without GPU data.
