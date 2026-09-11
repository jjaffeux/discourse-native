# Users scrolling — 2026-09-11

Reproduce the instrumented workload with:

```sh
flutter test --no-pub tool/benchmarks/users_scroll_benchmark.dart
```

The benchmark uses the production UsersPage with 1,000 rows, ten metric columns,
avatar fallbacks, and a stationary mouse over the scrolling table. It advances
240 frames in 40-pixel steps down and back up. It reports widget rebuild counts,
median/p95 pump wall time and total time. These are debug widget-test workload
measurements, **not native build/raster frame timings**. Avatar downloads,
decoding and server pagination are excluded; machine load affects timings.

Two baseline runs at `461e663c` and two runs with the fix:

| Measurement | Before | After |
| --- | --- | --- |
| Widget rebuilds | 115,887 | 111,534 |
| Median pump | 12.5–13.7 ms | 9.5–11.1 ms |
| p95 pump | 20.4–21.8 ms | 16.8–18.5 ms |
| Total 240 pumps | 3.22–3.37 s | 2.46–2.82 s |

Two sources of redundant work were removed in DTable:

- Hover previously called setState on the table fragment, rebuilding its layout,
  semantics wrappers and cell presentation. A value listener now updates only
  the hover decoration, keeping cell children stable and preserving the existing
  animation, selected/expanded colors and pointer behavior.
- Layout measured every cell with loose height and then laid every cell out
  again at the row height, even when it already had that exact height. Only
  shorter cells now need the second layout, preserving vertical alignment and
  natural heights for wrapped content, avatars and large text.

A render-probe regression counts two layouts for two equal-height cells and
zero further layouts when hovering between them. The baseline fails with four
initial layouts. Existing table tests cover unequal/wrapped cells, RTL, large
text, footer/caption, hover styling, resizing and scrolling. No fixed row height
or reduction in visible data was introduced.

## Follow-up: native profiling and real-session capture

The debug timing reduction above did not establish that the user's remaining
lag was fixed. A macOS **profile-mode** run now uses
`tool/benchmarks/users_native_scroll.dart`, warms the viewport, then scrolls down
and up twice while collecting native `FrameTiming` samples. Run it with:

```sh
flutter run --profile -d macos -t tool/benchmarks/users_native_scroll.dart
```

It logs `NATIVE_SCROLL` JSON and exits automatically. The fixture uses 1,000
users, ten metric columns, avatar fallbacks and no server pagination; it does
not reproduce real avatar I/O or trackpad input. Recorded on the native 1280px
window at approximately 120 frames/second:

| Native metric | Previous main | Shared row hover |
| --- | --- | --- |
| Frames | 1,960 | 1,964 |
| Build p95 | 1.186 ms | 1.231 ms |
| Raster p95 | 0.781 ms | 0.742 ms |
| Build/raster frames over 16.67 ms | 0 / 0 | 0 / 0 |

These results show **no meaningful native frame-time improvement** and do not
reproduce the reported lag. The further simplification shares one hover
animation per virtual row, preserving per-cell semantics, row colors, natural
height and the caption's separate background. It lowers the debug workload's
widget rebuild count from 111,534 to 35,128; that allocation/work reduction must
not be presented as an equivalent native speedup.

The existing Diagnostics > Topic scroll capture now records the Users route.
Start capture, close Diagnostics, scroll the affected Users table for 5–10
seconds, wait one second, then stop capture and copy the performance report.
It includes directory row/column counts, row and page builds, horizontal and
vertical scroll events, metric-maxima derivation cost, frame timings and the
existing slow-frame CPU/raster collection. No usernames, group names, metric
values, avatar URLs or site URLs are added. Instrumentation is dormant until
capture is armed. A fast-pointer-scroll regression verifies that scrolling
creates row events without rebuilding the Users page or recomputing maxima.

A capture from the affected session is still needed to identify the remaining
bottleneck rather than inferring it from offline timings.
