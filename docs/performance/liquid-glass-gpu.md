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

## System glass

`NativeGlass` (`lib/src/ui/foundation/native_glass.dart`) draws opted-in glass
with iOS 26 `UIGlassEffect` views that `GlassRenderer`
(`ios/Runner/GlassRenderer.swift`) adds above the Flutter view. The render
server composites them outside Flutter's frame, so that glass costs Flutter no
backdrop reads. Five `NativeGlassScope`s opt in: the mobile dock, the reader's
header row, the topic progress pill, the floating date in chat and topics, and
the chat composer's send button.

Flutter keeps the widgets, their layout, animations, gestures and semantics.
After each frame it reports every glass shape's frame, corners, tint and
opacity, and each scope's clip and paint order, and only sends when they
changed. The content drawn above the glass is captured as an image when it
repaints; Flutter composites its own copy at 1/255 opacity, so touches and
semantics still land on it. The native views never take touches. A merging
scope renders touching shapes as one through `UIGlassContainerEffect`, as the
header's joined bookmark and notification controls look in Flutter glass.

UIKit draws above everything Flutter shows. A scope therefore draws Flutter
glass while its route is covered, while a sheet covers it through its closing
transition, and while any `NativeGlassOccluder` is mounted. Every overlay in
the app mounts one: popovers, tooltips, hover cards, the composer's
suggestions and selection toolbar, post actions, text selection, embeds and
YouTube players. `native_glass_test` fails when a file opens an `OverlayPortal`
or `OverlayEntry` without one. The mobile composer sheet covers the shell
without a route or an overlay, so it mounts one too; `composer_docking_test`
pins it. Hosts without iOS 26 keep the Flutter glass.

An earlier prototype embedded `UIGlassEffect` as a platform view instead; Flutter
then splits its frame around the view, which cost about as much as the glass.

Interleaved on the phone, both sides with the edge bands, 120 fps throughout:

| Screen | Flutter glass | System glass | Render server change |
| --- | ---: | ---: | ---: |
| Topic list | 670 ms/s | 513 ms/s | +46 ms/s |
| Topic reader | 718 ms/s | 552 ms/s | +36 ms/s |
| Chat, dock only | 736 ms/s | 524 ms/s | about 0 |

The chat row comes from an earlier run with only the dock on system glass; the
run with every scope lost its chat trace. The reader's header retracts while it
scrolls, which already removes its glass, so the reader saves about the same
with or without the header and progress pill on system glass.

`NativeGlass.disabled` switches every scope back to Flutter glass at runtime
for side-by-side measurement.

## Shell under the reply sheet

The mobile reply sheet is a retained `DSheetViewport` above the whole shell.
Its full-height backdrop is an opaque canvas until a swipe fades it, yet
Flutter kept painting the reader underneath on every frame: its posts, panel
edges and, behind the sheet's occluder, the header, progress pill and dock as
Flutter glass. `DSheetViewport.covering` now reports while the canvas hides
everything beneath it, and the composer host skips painting the shell then. A
swipe paints it again in the same frame.

Interleaved on the phone, profile build, typing about 10 characters per second
into the reply sheet over a topic, 2-second windows, 5 per variant. The skipped
row was measured with a prototype that took the shell offstage:

| Variant | Raster thread per frame | Frames drawn per second |
| --- | ---: | ---: |
| Shell painted | 15.6 ms (15.2-17.2) | 62.5 |
| Shell skipped | 5.1 ms (4.7-7.6) | 101.9 |
| High contrast | 1.6 ms (1.4-2.0) | 99.7 |

The live binding draws every vsync, so frames drawn shows where the raster
thread saturates; the app requested about 12.5 frames per second in every
variant. On the simulator the shipped change measured the same as the
prototype, 221 against about 800 ms of raster time per second. Metal System
Trace recordings of these runs came back empty (Xcode 27.1, iOS 26.6.2), so
the GPU share is not measured.

## Open costs

- With the system dock, the topic list still measures about 524 ms/s against
  350 under high contrast. Glass mode also adds translucent panels,
  anti-aliased clips and the panel `saveLayer`; the last one measured no cost.
- With the Flutter dock, its fold puts a fractional `Opacity` above live glass,
  which the package seeds with a second backdrop read (`_OpacitySeedLayer`).

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
