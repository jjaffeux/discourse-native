# Channel scrolling

The channel's floating date separator and jump-to-latest visibility used to
call `setState` on the entire message stream. Moving between days rebuilt the
viewport, regenerated its row identities, and rebuilt already mounted message
tiles. A 500-message local fixture reproduced 40 stream rebuilds and 649
rebuilds of existing message tiles across slow scrolling and fast jumps.

The stream now publishes these two pieces of scroll chrome through the existing
`FrameSafeValueNotifier`. Only the date separators and jump button listen;
message rows keep their existing widgets. Live-message counts, read dwell,
history pagination, highlighting and selection still use their existing owners.
Changes to measured row extents invalidate and reschedule the floating-date
calculation without rebuilding the stream.

The native CPU capture also found HTML parsing and text layout in slow fast-jump
frames. The viewport inherited a cache area that constructed extra rich-message
rows outside the screen. Setting the existing Native scroller's `cacheExtent`
to zero confines that work to visible rows; no UI-kit API was changed.

## Reproduce

```sh
flutter run --profile -d macos -t tool/chat_scroll_profile_main.dart \
  --dart-define=SCROLL_LABEL=fixed
```

The fixture mounts the production `ChatChannelView`, using fake transport and
500 locally generated messages with multiple authors, wrapped HTML, lists,
inline code and daily separators. It scrolls 360 frames at 10 logical pixels,
then 12 frames at 1200 pixels in each direction. JSON reports are written to
the application's system temporary directory; their paths are printed.
`SCROLL_WIDTH=360` and `SCROLL_DARK=true` select the narrow dark variant.

Chat events also participate in the existing diagnostics scroll capture:
`chat.capture.context`, `chat.stream.built`, `chat.row.built`,
`chat.floatingDay.changed`, `chat.scroll.notification` and `chat.viewport.work`.
The capture joins these with engine frame timings and available VM CPU samples.
No event maps or timestamps are collected while the capture is disarmed, and
chat event fields contain counts, row indices and timings, not message bodies
or account identities.

## Regression checks

At 800 logical pixels, the widget test's slow/fast/return sequence now produces
zero stream rebuilds, 245 row builds (previously 1039), and zero rebuilds of
existing message tiles (previously 649). The 360-pixel dark variant also passes,
with zero stream/message rebuilds and 168 row builds.

The assertions allow at most two edge-row reactivations per fast jump, because
the virtualizer corrects estimated heights by detaching and reattaching rows.
Fast jumps must also build no more than the visible message count plus three
rows for date separators and estimated edges.
The regression tests also verify disarmed recording, date movement, and capture
context; the existing lifecycle tests cover live arrivals, deleted messages,
read dwell, date pinning, pagination, selection, highlights and keyboard jumps.

`dart analyze` passes. The focused scroll, channel lifecycle, thread workspace
and capture tests pass (73 tests, including both performance layouts).
The jump-button keyboard test traverses one available focus cycle instead of
assuming the control always follows ten Tab presses; it remains reachable and
activates with Enter after traversing the visible message actions.
Broader chat-shell testing reproduced three existing
layout failures on both this change and the untouched `df0e0b67` baseline:
panel-switcher centering (150 versus 152), grouped-channel header size (32
versus 25), and newest-message toolbar bounds (829 versus 827).

## Native measurements

macOS profile build, Flutter 3.47.2, Skia/Metal, 120 Hz (8.33 ms frame budget),
800-pixel light fixture. Both captures enabled Dart CPU profiling using the
Flutter tool's desktop engine switches. Each run used identical fixture data
and scroll deltas. The baseline is `df0e0b67` plus observational instrumentation.
The compact evidence is in [chat-scrolling.json](chat-scrolling.json):
`fixed` isolates the chrome change, and `final` includes the cache change.

| Scroll | Baseline UI p95 | Final UI p95 | Baseline over budget | Final over budget |
| --- | ---: | ---: | ---: | ---: |
| Steady | 1.99 ms | 1.98 ms | 1 / 360 | 0 / 360 |
| Fast | 10.09 ms | 6.62 ms | 4 / 13 | 0 / 12 |
| Return | 9.56 ms | 4.18 ms | 2 / 13 | 0 / 12 |

Native row builds fell from 541/452/430 to 60/119/116 for the three phases.
The baseline's extra fast/return frame is its trailing whole-stream rebuild.
The steady baseline overrun was raster work; none of its steady UI frames
exceeded budget. These are short local-data captures, not measurements of
network image loading, arbitrary live channels, or other platforms.

Native interaction review covered mouse scrolling across date separators and
jump-to-latest returning to message 500 and hiding the jump button, in both
800-pixel light and 360-pixel dark fixtures. The narrow native run's UI p95
was 1.66/4.23/3.41 ms for steady/fast/return, with no UI overruns and one
steady-scroll raster overrun. No iOS, Android or Linux device run was performed.
