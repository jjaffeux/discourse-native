# Media-heavy topic scrolling

Measured on October 29, 2026, against `main` at `7c99db78f`, on an iPhone 15
Pro Max (iOS 27.0.1) in profile mode at 1290 by 2796 pixels, 3x density and
120 Hz.

Reading down a topic dropped a frame about once a second. Each drop was a
reply entering the scroll cache: its header, footer, reactions and HTML body
were built and laid out in one frame, which took 8 to 18 ms against an 8.3 ms
budget. Replies first built while the reader scrolls toward the end now build
their HTML in a later frame. No frame of the measured read exceeds the budget
any more.

## Workload

`integration_test/topic_media_scroll_profile_test.dart` mounts the production
`TopicView` with 120 replies. They carry lightboxed JPEG photos with `srcset`,
PNG screenshots, animated GIFs, still and animated AVIF, emoji, code blocks,
quotes, likes and up to five reactions each. All bytes are generated or
embedded and served from memory, so the run needs no forum. Semantics are
off, as on a phone without assistive technology.

The cold phase swipes 2,000 pixels a second from the first reply to the last:
every reply is built and every image fetched and decoded as it scrolls in. The
warm phase swipes back to the top over replies the retention budget has
released. Each phase records frame timings and, unless `PROFILE_CPU=false`,
the UI isolate's CPU samples at 4 kHz. Sampling costs frame time, so timing
comparisons run without it.

## Where slow frames went

The samples taken inside frames that built for more than 4 ms were folded per
frame. Two findings shaped the fix:

- Every slow frame was mounting and laying out one new reply. The largest
  named costs were paragraph layout (17% of slow-frame samples), the HTML
  body's parse and widget tree (13%, two fifths of it parsing), text span
  construction (4%), and `RenderObject.attach` describing semantics for every
  new render object even with semantics off (3%). The rest was spread over the
  roughly 800 elements of a reply, most of them UI-kit chrome.
- With the HTML body replaced by a fixed-height box, and CPU sampling on, no
  frame exceeded 7.6 ms (p99 4.3 ms) where the unchanged build had 63. The
  body is what pushes a reply's frame over budget.

Raster time was not a factor: its p99 stayed between 1.8 and 3.8 ms. Image
resolution inside slow frames was mostly profile-mode timeline bookkeeping,
which release builds compile out. In the timeline run, scavenges of about
5.5 ms ran 1.7 times a second, almost all of them inside the engine's idle
notification between frames.

## Change

The reader decides, once per reply, whether a reply first built during a
user drag or fling builds its HTML in a later frame. Toward the end of the
stream, the reply is entering the scroll cache below the viewport, so its
`CookedHtml` uses the asynchronous build. The vendored `HtmlWidget` parses such a short document in a microtask
after the frame instead of in an isolate (see its `PATCHES.md`), and mounts
the body in a later frame. The reply reports the pending body through
`HtmlBodyMountingNotification`, as long replies already do, and initial
positioning never happens during a user scroll.

Toward the start, a reply enters above the viewport, and a body landing late
there would push the visible replies down; a widget test showed 252 px. Such
a reply is staged only when the list has measured it before, as when the
reader scrolls back over replies it released. It then holds that measured
height until its body lands, so nothing moves; a reply the list never
measured builds at once. Jumps and keyboard navigation land on visible
replies and also build at once.

## Results

Each round alternates a build with the change and one without it, both with
CPU sampling off. Times are frame build durations of the cold phase in
milliseconds.

| Run | Frames | p50 | p99 | Max | Frames over 8.3 ms |
| --- | ---: | ---: | ---: | ---: | ---: |
| Without, round 1 | 5,467 | 0.40 | 7.62 | 17.55 | 33 |
| With, round 1 | 5,482 | 0.39 | 4.19 | 7.16 | 0 |
| Without, round 2 | 5,466 | 0.40 | 6.93 | 14.90 | 16 |
| With, round 2 | 5,485 | 0.39 | 4.12 | 7.52 | 0 |
| Without, round 3 | 5,451 | 0.39 | 7.17 | 16.58 | 21 |
| With, round 3 | 5,489 | 0.38 | 3.96 | 7.27 | 0 |

The remaining maximum matches the body-less experiment: a reply's chrome
alone. Frames whose whole pipeline, vsync to raster, exceeded 8.3 ms fell from
94, 61 and 77 to 2, 4 and 1. Round 3 ran the committed fixtures; the first
two used larger AVIF files.

With 4 kHz CPU sampling on both sides, the cold phase had 5 frames over
budget instead of 63, and the HTML widget's parse and tree fell from 11.5% to
0.5% of the samples taken inside slow frames. Its three slowest frames, 14 to
16 ms, held 3 to 11 samples each where 4 kHz sampling takes about 60: the UI
thread spent them outside Dart code, in collection or descheduled.

Those rounds staged replies toward the end only. A second change staged
remeasured replies toward the start, measured on the warm phase, which reads
back up over replies the reader has released:

| Run | Frames | p50 | p99 | Max | Frames over 8.3 ms |
| --- | ---: | ---: | ---: | ---: | ---: |
| Toward the end only, round 1 | 5,464 | 0.39 | 6.94 | 9.97 | 17 |
| Both directions, round 1 | 5,482 | 0.39 | 4.20 | 15.41 | 2 |
| Toward the end only, round 2 | 5,470 | 0.39 | 6.98 | 15.46 | 23 |
| Both directions, round 2 | 5,483 | 0.40 | 4.19 | 7.92 | 0 |

The cold phase stayed between 0 and 4 frames over budget in all four runs.
The first run with the change had 4 of those, up to 14.9 ms, in its cold
phase, which both builds handle alike; its warm-phase maximum is likely the
same disturbance.

The per-run summaries are in
[data/topic-media-scrolling.json](data/topic-media-scrolling.json).

## Not changed

- Scrolling toward the start over replies the list never measured, as after
  opening a topic at its last post, still builds each one in one frame.
- A reply's UI-kit chrome (buttons, tooltips, hover cards) is most of its
  elements and most of the remaining frame time.
- `RenderObject.attach` computes semantics configurations with semantics
  disabled. That is the framework's cost.

## Reproduce

Profile builds need local signing, as in
[pane-resizing.md](pane-resizing.md). On a phone, give the Profile
configuration its own bundle identifier first: `flutter drive` replaces and
then uninstalls an app with the same one.

```sh
flutter drive --profile -d <device-id> --no-dds \
  --driver integration_test/performance_driver.dart \
  --target integration_test/topic_media_scroll_profile_test.dart \
  --dart-define=PROFILE_LABEL=current
python3 tool/topic_media_scroll_profile.py build/integration_response_data.json \
  --output /tmp/topic-media
```

The tool writes a flame graph per phase, one restricted to slow frames, and a
focused variant of each without element, layout, zone and native plumbing.
`--dart-define=PROFILE_CPU=false` measures timing alone. With
`--dart-define=PROFILE_TIMELINE=true --endless-trace-buffer`, the run records
six swipes of the cold phase with per-widget build, layout and paint events
instead; those events slow every frame, so use them to attribute work, not to
time it.

If Homebrew's `rustc` precedes rustup's proxies on `PATH`, the AVIF native
asset fails to build for x86_64 and iOS. Put `$(brew --prefix rustup)/bin`
first.
