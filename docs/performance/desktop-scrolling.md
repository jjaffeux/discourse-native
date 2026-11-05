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

## GPU time

Measured the same day on the same machine, after the hatch fix, with Metal
System Traces of the warm timing pass of every route.

### What the busy share counts

The 40 to 50% GPU busy share from `ioreg` is system-wide. While these runs
were recorded, World of Warcraft was also running. It took 21 to 27% of the
GPU in every window, and up to 84% in a later one. Discourse took 24 to 30%,
and the window server about 3%. Busy shares also depend on the GPU's clock.
The GPU spent most windows in its Minimum performance state, and an encoder
took about 30% longer there than in the Medium state. The driver therefore
reports each encoder's mean duration for each performance state, and the
comparisons below hold the state fixed.

### Per pass

A frame of the topic list has these GPU passes, at the Minimum state:

| Pass | Per frame | Fragment µs | Vertex µs |
| --- | ---: | ---: | ---: |
| Onscreen pass | 1 | 1,060–1,170 | 210–250 |
| Edge-fade `ShaderMaskLayer` offscreens | 3 | about 100 each | about 35 each |
| Blend-filter passes (`PipelineBlend`) | 4 × 3 | 20–60 each | about 8 each |
| `FramebufferBlendContents` snapshot | 1 (3–6 on topic and chat routes) | 20–50 each | about 6 each |

The three mask offscreens are the 298 by 96 point toggle group, the sidebar,
and the main panel. Together they cost about 0.3 ms of fragment time and
0.1 ms of vertex time. The onscreen pass is the largest owner.

### Inside the onscreen pass

A local experiment build, not committed, repeated a topic-list pass with one
suspect switched off at a time. The onscreen pass's fragment time at the
Minimum state was:

| Variant | Fragment µs |
| --- | ---: |
| Baseline (three passes) | 1,061–1,171 |
| Edge fades off | 1,061, plus the three mask passes removed |
| Cast shadows off | 1,113 |
| Inset rim and catch of light off | 711 |
| Highlight clipped to its top band | 1,183 |
| No rounded-rectangle clips in the inset painter | 1,176 |

Removing the rim and the catch of light saved about 430 µs. Shrinking their
clips and their highlight geometry saved nothing, so the cost is the rim's
own draw.

On macOS, Impeller always renders with signed distance fields (the engine
test is `EnableSDFsAlwaysReturnsYes`). `Canvas::DrawRoundRect` renders a
rounded rectangle with circular corners as one `UberSDFGeometry` quad. That
quad covers the shape's whole bounds, whether the shape is filled or
stroked. Every panel's 1px rim therefore shaded and blended a quad the size
of the panel on every frame. On desktop, the workspace panels and the page
panels each draw a rim.

### Change

`_InsetEdgePainter` in `surface_depth.dart` now clips the rim's draw with a
difference `clipRect` before it strokes the rim. The clip removes the middle
of the shape, which starts 2 pixels inside the largest corner on each side.
The rim and its antialiasing never reach that rectangle, so no pixel changes.
On Impeller, a difference clip of a rectangle is one depth-only draw. The
SDF's fragments in the middle then fail the depth test before they are
shaded.

`surface_depth_test.dart` compares the painter with a reference that strokes
the rim the old way. The comparison is byte for byte, for panel, rim and
block depths in both brightnesses. It covers circular, elliptical, square
and oversized radii, with and without a border, at fractional offsets and
scales of 1, 1.5 and 2. A margin of 0.5 or -1 pixels instead of 2 fails it.

### Results

Four runs alternated baseline and fix (A, B, B, A), with a Metal window in
the warm timing pass of every route. In the last baseline run, a game took
74 to 92% of the GPU in every window except the side-by-side channel. The
channel window was not recorded. Those windows are left out. An earlier
attempt was discarded for the same reason, with World of Warcraft at up to
84%.

The table shows the onscreen pass's mean fragment time in the Minimum
performance state, where the GPU spent 88 to 100% of each kept window.

| Route | Baseline µs | Fix µs |
| --- | ---: | ---: |
| Topic list | 3,017 | 2,734 / 1,849 |
| Topic | 3,031 | 1,520 / 1,880 |
| Channel | 1,517 | 933 / 939 |
| Side by side, topic | 1,420 | 1,315 / 1,380 |
| Side by side, channel | 1,645 / 1,834 | 1,150 / 896 |

The fix is lower on every route. In the cleanest comparison, side by side
with the channel and two runs of each, the cut is 41%. The spread is wide.
The topic list's baseline here is three times the earlier windows' value in
the same state, because the Minimum state still covers a range of clocks.
The mask passes and the vertex time did not change. Discourse's own busy
share went from 44 to 51% in the baseline run to 30 to 45% with the fix.
Frame timings did not change: raster and build stay under 2 ms on average,
and the raster thread stayed on the fast core tier in every kept window.

## Remaining work

- Repeat the rim measurement with no other GPU workload, and with the GPU
  held at one clock if a tool allows it. The Minimum state still covers a
  wide range of clocks.
- The edge-fade masks cost about 0.4 ms of GPU time per frame across three
  offscreen passes. A replacement that leaves pixels unchanged needs the
  backdrop under each fade to be one opaque color, and the sidebar's is not
  known to be.
- The blend-filter and framebuffer-blend passes, four to six a frame, are
  not attributed to widgets yet.
- Chat message bodies now mount a frame after their row while the reader
  scrolls; see [Chat history](#chat-history). The slower core tier was not
  reproduced faithfully for that change.

## Chat history

Measured the same day on the same machine, on top of the hatch fix.

On the slower core tier, a cold chat scroll had about 2% of frames over
8.33 ms of build, up to 21 ms. Each one mounted a new message: paragraph
layout, paragraph building and the HTML body's element tree. The chat list
has no cache extent, so a row is built in the frame it enters the viewport.

Chat rows now follow the topic reader's policy (see
[topic-media-scrolling.md](topic-media-scrolling.md)). A row first built
during a user scroll builds its `CookedHtml` in a later frame.
`ChatMessageBodyStaging` latches that choice when the row is first built. The
transcript is reversed, so the edge a row enters from decides:

- A row entering from history lies beyond the visible rows, and a body
  landing late grows away from them.
- A row entering from the present lies below them. It is staged only when the
  list has measured it before, and it keeps that height until its body lands.

Jumps, programmatic positioning and live arrivals build at once. A deferred
short body used to show the HTML package's loading spinner for one frame. The
spinner was taller than a one-line message, so the row shrank when the body
landed. It now loads as an empty box.

Runs alternated baseline and change. The first baseline run was discarded:
another application held most of the GPU, and its cold pass produced 176
frames. Build times in milliseconds, cold chat pass, about 1,545 frames each:

| Run | p99 | Max | Over 8.33 ms | Frames over 4 ms | UI-thread samples on the fast tier |
| --- | ---: | ---: | ---: | ---: | ---: |
| Change, 1 | 1.56 | 2.55 | 0 | 0 | 100% |
| Change, 2 | 1.57 | 2.37 | 0 | 0 | 100% |
| Baseline | 2.67 | 6.49 | 0 | 3 | 97% |

The core tier is from the Instruments samples of the main thread, which runs
the UI isolate. All three runs stayed on the fast tier, where the baseline was
already within budget. Every chat pass, including the warm and side-by-side
passes, lowered its build p99 by about 40%. The other routes did not change.
The HTML parser and build tree took the same 1.5% of cold-pass samples before
and after. That work now runs in a later frame instead of in the frame that
mounts the row.

To reach the slower tier, a second round launched both builds under
`taskpolicy -c background`. That kept the main thread on the slower tier for
every sample, but it also cut each cold pass to about 170 frames, so each
frame carried about ten times the scroll distance. Both sides then had 7 to 13
frames over budget. Those frames held one or two CPU samples where 4 kHz
sampling takes about 40, so the thread was mostly descheduled. Of the samples
taken inside frames that built for more than 4 ms, 3 to 8% were HTML parsing
and building in the baseline and none with the change. That round shows
where the work went. It does not answer whether a natural slower-tier run
stays under budget.

`chat_message_body_staging_test.dart` pins the deferral in both directions.
It also pins that the visible rows keep their place when a body lands.

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
(`.native.<thread>.svg`), and the raw JSON and trace. `--trace none` skips
Instruments. `--reanalyze` rebuilds the report from a previous run's files.

`--trace metal` records a Metal System Trace instead of a Time Profiler.
A Metal trace of a whole run is tens of gigabytes, and `xctrace` cannot
export it. The driver therefore records `--gpu-seconds` (default 4) at the
start of each pass that matches `--gpu-phases` (default `warmTiming$`). For
each window, the report gives:

- the GPU busy share of every process,
- the time in each GPU performance state,
- the app's encoders per frame, with mean, p90 and per-frame time,
- the mean encoder time for each performance state,
- the CPU samples, with the core tier of each thread.

Close other GPU workloads first, such as games.
