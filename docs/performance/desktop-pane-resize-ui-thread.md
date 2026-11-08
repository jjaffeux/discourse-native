# Desktop pane resizing on the UI thread

Dragging the sidebar edge or the seam between two document panels changes a
width on every pointer tick. Most of that tick's UI-thread work was rebuilding
widgets under `LayoutBuilder`s whose output did not depend on the new width.
The changes below remove that work without changing what a pane shows.

The earlier investigation in [pane-resizing.md](pane-resizing.md) describes
raster cost with the retired glass rendering. Without glass, raster is about
1 ms per frame here, so the UI thread is the larger cost.

## Result

Five alternating runs per side of `integration_test/panel_resize_performance_test.dart`,
in compiled macOS profile builds, on an Apple M5 Pro with a 1280 by 942 point
window at 2x. Baseline is `f00de6dc2`. Each drag is 240 two-pixel ticks after a
warm-up. Median of the runs, with the range across runs:

| UI thread per frame | Baseline | Updated | Change |
| --- | ---: | ---: | ---: |
| Sidebar drag, mean | 1.72 ms (1.65–1.95) | 0.99 ms (0.97–1.25) | −43% |
| Sidebar drag, p95 | 2.18 ms (2.00–2.77) | 1.23 ms (1.20–1.56) | −44% |
| Panel seam drag, mean | 2.27 ms (2.18–2.75) | 1.41 ms (1.29–1.59) | −38% |
| Panel seam drag, p95 | 2.96 ms (2.75–4.15) | 1.90 ms (1.86–2.05) | −36% |
| Reader scroll (control), mean | 0.25 ms (0.20–0.28) | 0.25 ms (0.22–0.31) | none |

The ranges for both drags do not overlap, and the scroll, which resizes nothing,
did not move. Raster time showed no measurable difference: 0.84 ms against
0.83 ms for the sidebar and 1.01 ms against 0.94 ms for the seam, inside the
run-to-run spread.

Each case resized its pane by the full 120 pixels and drew at least 240 frames.
The updated build drew 253 frames per case and the baseline about 267; those
extra frames were not attributed. The display was locked when the runs started
and unlocked by the end, and GPU use rose from about 29% to about 60% in the
last rounds, on both sides.
Summaries are in [pane-resize-native.json](data/pane-resize-native.json).

In this fixture every frame already fit the 8.3 ms budget of a 120 Hz display
before these changes. The gain is headroom for larger forums, slower machines,
and other work in the frame; no dropped-frame improvement was measured here. In
a debug-mode phase split of the same drags, layout of what really changed is
now the largest share, ahead of the remaining builds and paint.

## What each change saved

`test/desktop_panel_resize_work_test.dart` counts widget builds over 20 drag
ticks in the shell fixture at 1440 by 900, with a list and a topic open beside
each other. The counts repeat exactly between runs. These are the macOS counts
in order of application, in widget builds per tick; the final counts are the
same on Linux and Windows:

| Change | Sidebar drag | Seam drag |
| --- | ---: | ---: |
| Baseline | 693 | 2,270 |
| `DFitRow` skips the step it would discard | 693 | 1,899 |
| `DFitRow` keeps its step unless an earlier one could fit | 693 | 1,215 |
| List header controls select their layout | 693 | 961 |
| Sidebar fills its parent instead of measuring it | 363 | 961 |
| Title bar rebuilds at its breakpoints | 283 | 961 |
| Reader toolbar and page body are retained | 231 | 911 |
| Document tabs and the tab strip are retained | 191 | 648 |
| Topic row taxonomy rebuilds when its fit changes | 191 | 536 |
| Each workspace pane is retained | 191 | 304 |
| Search field rebuilds at its breakpoints | 125 | 304 |
| Panel chrome and the swap control are retained | 70 | 249 |

Before the `DFitRow` changes an element could build several times in one tick:
2,270 builds touched 1,226 elements. It now builds once, which the test checks.
[pane-resize-work.json](data/pane-resize-work.json) has the counts and the
widget responsible for the rebuilds at the start and the end.

These counts are the work removed. They are not latency; the table above is the
timing. The fixture has a short sidebar and a short list, so a real forum has
more rows to skip. That larger case was not measured.

## How it works

`DLayoutSelector` is a `LayoutBuilder` whose builder runs again only when a
value derived from the constraints changes. Its builder has its own context, so
inherited dependencies still rebuild it when the selection holds.

`DFitRow` used to restart from its first step on every change in room, which
also moved views in and out of the feed menu's overflow within one layout. A
step that overflowed holds its adaptive controls at their minimum, so it needs
at least the room it overflowed by. The row remembers that room and restarts
only when it is reached, when a control's own width at the settled step changes,
or when the room crosses a breakpoint a control reports through
`DFitRow.reportRoomBreakpoint`, as the category path does. A sweep test in
`test/d_fit_row_test.dart` compares every width in both directions with a fresh
layout.

What still runs on each tick: the topic list's reading lane, which rebuilds its
sliver delegate at a new width, and the layout of everything whose width really
changed.

## Reproducing

```sh
flutter test test/desktop_panel_resize_work_test.dart
```

The test fails if a drag rebuilds more than its budget, or if any element builds
twice in a tick. For native timing, follow the build and `tool/benchmark_panel_resize.py`
steps in [pane-resizing.md](pane-resizing.md#reproducing); run it only on a quiet
machine, since it opens a window.
