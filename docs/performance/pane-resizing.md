# Desktop pane resizing

Investigated on October 23, 2026, against `e9496b05e` and `main` at
`2ef563165`, on an M5 Pro Mac with a 120 Hz ultra-wide display (2560 by 1080
points at 2x), using profile builds.

Dragging the sidebar edge or the seam between the two document panels felt
slow on macOS. The frames are bound by the GPU, and glass-mode painting is most
of that work: the Flutter glass lenses, the window's palette pools, and the
reading panels' rim. The drag itself asks little of the UI thread, and the one
avoidable rebuild on its path was already removed by `820f2fdf6`, which stopped
a sidebar drag from rebuilding the whole wide shell.

## Glass bounds a resize frame

`integration_test/panel_resize_performance_test.dart` opens the tab-switch
fixture with a topic list in the main panel and a 60-post topic in the
secondary panel. It drags the sidebar edge, then the panel seam, by 60
two-pixel steps out and back twice, one frame per step, and then scrolls the
reader for the same number of frames as a control. Each case reports
`FrameTiming` build and raster times for its measured frames.

Medians of five alternating runs per side, with the window zoomed to 2540 by
1030 points:

| Case | Build mean | Raster mean | Raster p95 | Raster mean, high contrast |
| --- | ---: | ---: | ---: | ---: |
| Sidebar drag | 3.37 ms | 9.08 ms | 10.11 ms | 1.63 ms |
| Panel seam drag | 4.35 ms | 10.35 ms | 11.13 ms | 1.51 ms |
| Reader scroll | 0.52 ms | 6.30 ms | 6.90 ms | 2.16 ms |

High contrast resolves every glass surface to its opaque fill, which removes
glass from a frame without changing the layout.

A 120 Hz display leaves 8.3 ms per frame. The UI thread fits with room to
spare. The raster thread does not: both drags miss the budget on most frames.
Scrolling pays the same glass and stays inside it. With glass off, a drag frame
rasterizes no slower than a scrolled one, so the 3 to 4 ms a resize adds is
glass too.

Raster time rises with the window's pixel count and with any other GPU work on
the machine. Over one afternoon, the same code measured from 9.5 ms to 30 ms
per seam-drag frame as other applications drew. High contrast stayed between
1.5 and 3.7 ms through the same runs, so glass is the part that degrades.
Compare builds only when their runs alternate.

A three-second `sample` of the raster thread during seam drags at the zoomed
size puts 41% of its drawing time under `GaussianBlurFilterContents` and 13%
under `Canvas::FlipBackdrop`, the backdrop reads behind glass. About half of
the drawing time is spent blocked in `-[_MTLCommandBuffer initWithQueue:]`,
which waits for the GPU to retire earlier command buffers. During a reader
scroll the blur share is 52% and the wait is about the same. Allocating
offscreen targets, which a resize might be expected to churn, is 5% during the
drag and 2% during the scroll.

## The drag's UI work

A debug rebuild count over five drag ticks found about 1,050 elements rebuilt
per sidebar tick and 1,270 per seam tick. Nearly all of them sit below
`LayoutBuilder`s that run again whenever their width changes: the sidebar body,
the title bar, the composer dock, `DesktopPanels`, `MainContent`, `TopicView`
and the reading lanes. Topic rows and sidebar rows rebuild; post bodies do not.

Removing the wide shell's rebuild, the change `820f2fdf6` made, cut the
sidebar count by about 7% and did not move build time: 2.61 ms before and
2.57 ms after, five alternating runs each in a 1280 by 860 window. Skipping
`DesktopPanels`' `setState` on seam ticks left the count at 1,265 and was not
kept. The UI thread is not what makes these drags slow in this fixture. A
forum with a long sidebar or topic list rebuilds more rows per tick; that was
not measured.

## Where the glass time goes

Each variant below switched one glass-mode painter off, in one interleaved run
of five per side on a GPU that other applications already kept 60 to 75% busy.
Raster time per frame:

| Variant | Sidebar drag | Seam drag | Reader scroll |
| --- | ---: | ---: | ---: |
| Glass as shipped | 16.61 ms | 16.71 ms | 14.64 ms |
| No palette pools | 14.70 ms | 16.05 ms | 8.64 ms |
| No glass lenses | 15.80 ms | 16.08 ms | 10.11 ms |
| No panel rim | 16.47 ms | 16.60 ms | 12.90 ms |
| None of the three | 5.98 ms | 6.44 ms | 3.74 ms |

A drag only gets inside its budget once all three are cheaper: while the GPU
stays saturated, the raster thread waits on it either way. Leaving each one on
alone, in a second run, put its share of a drag frame at about 6 ms for the
lenses, 3.5 ms for the pools and 3 ms for the rim.

The pools and the rim's catch of light each filled a whole window or panel
with a gradient that is transparent over most of it. They now draw only the
pixels that change, with identical output (`448d00afa`). In a similar
interleaved run the trims cut the sidebar drag from 16.58 to 12.01 ms, the
seam drag from 16.91 to 11.87 ms, and the reader scroll from 14.65 to
10.23 ms.

## What is left

With the gradients trimmed, the Flutter lenses are the largest remaining cost.
Drawing them with the system material, as `NativeGlass` does with
`UIGlassEffect` on iOS 26, is the change that would take their backdrop reads
out of Flutter's frame.

## Options measured and not kept

- Painting each glass lens as a flat tint while a pane handle is held. Lens
  glass is only a third of the cost, and controls visibly change material when
  a drag starts and ends.
- Removing frost from every `DGlassSurface`. No difference larger than the
  run-to-run spread.
- The window's own `NSGlassEffectView` backdrop, and an opaque Flutter window
  background. Neither changed raster time.

## Reproducing

Profile builds need local code signing. Before building, set the `Runner`
target's Profile configuration to sign to run locally (`CODE_SIGN_IDENTITY =
"-"`, manual style, no team) with `Runner/Debug.entitlements`, and do not
commit that change.

Build one application per side. `PROFILE_RESIZE_MAXIMIZED` zooms the window
before measuring, and `PROFILE_RESIZE_HIGH_CONTRAST` turns glass off:

```sh
flutter build macos --profile \
  -t integration_test/panel_resize_performance_test.dart \
  --dart-define=PROFILE_LABEL=glass
cp -R build/macos/Build/Products/Profile/Discourse.app /tmp/glass.app
```

Then alternate them:

```sh
python3 tool/benchmark_panel_resize.py \
  --app glass=/tmp/glass.app --app high-contrast=/tmp/high-contrast.app \
  --output /tmp/pane-resize
```

The runner checks that every case completed, drew at least 120 measured frames,
and resized its pane by 120 pixels, and it retries a failed launch once and
counts it. It also samples the device's GPU utilization, which includes the
window server, for each case. It groups runs by window size: the app reopens
at its last window frame, and a zoom does not always reach the same size.

To find where a frame's time goes, add
`--dart-define=PROFILE_RESIZE_WIDGETS=true` and run the test with
`flutter drive --profile -d macos --driver integration_test/performance_driver.dart`.
Each case's timeline lands in `build/integration_response_data.json` with
per-widget build, layout and paint events. Those events slow every frame, so
use them to find work, not to time it.
