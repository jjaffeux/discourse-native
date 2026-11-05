# Desktop scrolling

Measured on November 5, 2026, against `main` at `ae225e426`, on an M5 MacBook
Pro with a maximized window of 2560 by 1050 points at 2x (5120 by 2100 pixels)
and 120 Hz, using profile builds.

Scrolling the topic list, a topic, or a chat channel on macOS dropped most
frames. The UI thread was not the cause: build time stayed under 4 ms at the
99th percentile on every route. The raster thread was. Each visible closed
topic row cost several milliseconds of raster time on every frame, whether or
not the list was moving.

## Workload

`integration_test/desktop_scroll_profile_test.dart` mounts the production
`DiscourseApp`, maximizes the window, and scrolls with synthetic trackpad pans
at 2,000 points a second. API payloads are generated in-process. Images are
served over loopback HTTP, so they travel the production fetch and decode path.

It runs five routes: the topic list, a topic, a chat channel, and the same
channel and a second topic side by side. On desktop, the first three still
show the Latest list in the second panel. Each route runs three passes: a cold
pass into unbuilt content, a warm pass back, both with Dart CPU sampling at
4 kHz and the Dart, Embedder and GC timeline, then an unprofiled warm pass for
timing.

`tool/profile_desktop_scroll.py` runs the app once and attaches an Instruments
Time Profiler to it, which attributes native raster-thread time to each pass.
It also polls the system GPU busy share.

## Where the time went

On the raster thread, 77% of the topic list's samples were under
`impeller::Canvas::DrawLine`, through `AttemptDrawLineSDF`,
`BlendFilterContents::RenderFilter` and `ContentContext::MakeSubpass`. The
lines were `_ClosedHatch` in `d_item.dart`. It paints a closed row's trailing
hatch as about 200 one-pixel diagonal strokes, each with a gradient shader.
Impeller cannot shade a signed-distance line directly, so it shades every
stroke in its own offscreen pass the size of the row. Impeller has no raster
cache, so a static row repeats all of this on every frame.

In the side-by-side route, the second panel showed a topic, so no closed row
was visible. That route already rastered in under 1 ms.

## Change

The hatch draws only the strokes that cross the inked band. That band is the
trailing 55% of the row, where the fade is not fully transparent. The strokes
stay on the same lattice and are drawn as one stroked path, which Impeller
renders as one gradient-filled geometry. The closed-row pixel test and the
topic-card goldens pass unchanged. `closed_topic_row_test.dart` now asserts
one draw per row at any width.

## Results

Four runs alternated baseline and fix (A, B, B, A). Frame timings are from the
unprofiled warm pass, except the topic list's cold pass. "Over" counts frames
above the 8.33 ms budget, out of about 1,550 per pass.

| Pass | Baseline raster mean ms | Over | Fix raster mean ms | Over |
| --- | ---: | ---: | ---: | ---: |
| Topic list, cold | 8.84 / 8.81 | 916 / 815 | 1.38 / 1.38 | 0 / 0 |
| Topic list | 9.03 / 19.19 | 907 / 667 | 4.52 / 4.64 | 17 / 17 |
| Topic | 8.40 / 12.63 | 337 / 1,008 | 3.63 / 3.70 | 3 / 3 |
| Channel | 5.83 / 13.24 | 6 / 960 | 3.88 / 4.03 | 12 / 17 |
| Side by side, channel | 0.86 / 0.92 | 0 / 0 | 3.03 / 3.13 | 12 / 14 |

The side-by-side rows got slower, and so did build times on most routes. The
work did not grow. Instruments records the core type for each sample. The
baseline's raster and UI threads ran almost entirely on the fastest core tier
because the hatch kept them busy. After the fix, macOS moved both threads to
the slower tier from the second route on, and the same work took about three
times as long. On the same tier, the topic list's cold pass needed 10,697
raster samples before and 1,982 after.

FrameTiming raster durations are wall time, so they include waiting for the
GPU and drawables. Raster CPU and frame timing can disagree.

## Remaining work

- The GPU stays 40 to 50% busy on every route after the fix. The candidates
  are the full-panel `ShaderMaskLayer` edge fades of the scroll views and the
  sidebar. Each renders its whole panel offscreen on every frame. Attributing
  GPU time needs a Metal System Trace.
- On the slower core tier, a cold chat scroll has about 2% of frames that take
  over 8.33 ms to build. Each one is mounting a new message: paragraph layout,
  paragraph building and its element tree. The topic reader already defers a
  new reply's HTML to a later frame. The chat transcript does not.

## Reproduce

Profile builds need local code signing, as in [pane-resizing.md](pane-resizing.md).
If Homebrew's `rustc` precedes rustup's proxies on `PATH`, put
`$(brew --prefix rustup)/bin` first.

```sh
flutter build macos --profile \
  -t integration_test/desktop_scroll_profile_test.dart \
  --dart-define=PROFILE_LABEL=current
python3 tool/profile_desktop_scroll.py \
  build/macos/Build/Products/Profile/Discourse.app --output /tmp/desktop-scroll/run
```

The run takes about four minutes and takes over the screen. It writes
`run.txt` with every table, a Dart flame graph per pass (`.svg`,
`.focused.svg`, `.folded`), native flame graphs per thread
(`.native.<thread>.svg`), and the raw JSON and trace. `--no-trace` skips
Instruments. `--reanalyze` rebuilds the report from a previous run's files.
