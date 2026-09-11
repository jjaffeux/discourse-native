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
