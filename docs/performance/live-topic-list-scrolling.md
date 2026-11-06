# Live topic-list scrolling (dev.discourse.org)

Scrolling the Latest list of a live forum costs **about 18% less UI-thread
CPU inside frames, 29% less building and 18% less layout**, with fewer than
half as many frames over an 8.33 ms build. The changes remove work that
every row repeated as it mounted, and the shell-wide rebuild a page of new
categories caused; see the [final comparison](#final-comparison). A row
mounts about 4% fewer elements and render objects, and the largest
app-level costs it paid on mount are gone or cut by an order of magnitude.
The slowest frame of a first pass, where a page brings categories the site
had not loaded, went from 5–9 ms to 2–4 ms.

The first round of changes, measured on its own while the machine was
otherwise idle, on the pass that mounts the most rows (19,200 px back up the
list, about 2,420 frames per run):

| Dart CPU in the pass | Baseline, ms | First round, ms |
| --- | ---: | ---: |
| Inside frames | 1,127 / 1,144 | 1,068 / 1,064 |
| Building (`BuildOwner.buildScope`, including layout-time builds) | 418 / 435 | 347 / 327 |
| Layout (`PipelineOwner.flushLayout`) | 422 / 443 | 385 / 379 |

Earlier reports cover the synthetic workload:
[topic-list scrolling](topic-list-scrolling.md),
[fast topic-list scrolling](fast-topic-list-scrolling.md) and
[topic-row composition](topic-row-composition.md). This one profiles the
production app against dev.discourse.org with the build's own signed-in
session, real avatars, emoji, categories and tags.

## What a row cost

The baseline is `d160c15d6`. On an Apple M5 Pro at 120 Hz the list was
already within budget: frame build p99 2.0–2.5 ms, raster mean 1.3–2.0 ms,
and at most one frame over 8.33 ms of build per 19-second pass. The cost
that remains is per row, paid in the frames where rows enter the viewport,
and it scales with slower devices and wider windows.

A desktop row with five posters, an excerpt, a category and tags mounts
about 1,100 elements, 480 render objects and 230 states. In the baseline
Dart CPU profile, the app-level work inside frames that stood out was:

| Cost | Share of in-frame samples |
| --- | ---: |
| `TopicTextMeasurements.measure` (footer text widths) | 4.3% |
| `ShellController._routeForLink` from `LinkTarget.build` | 1.3% |
| Implicit animation set-up and tear-down | 1.0% |
| `WidgetsBinding.removeObserver` | 1.0% |
| Edge-fade gradient creation | 0.7% |
| Tooltip scroll tracking on hover entry | 0.4% |
| Metadata text style derivation | about 0.4% |

Element inflation as a whole was 36% of in-frame samples, text layout 11%
and unmounting 8.5%. Those are spread over hundreds of small widgets.

## Changes

- **Text widths.** The footer measures its age, counts, tag and category
  names. The shared cache held 128 widths, fewer than a live list window's
  distinct strings, so most lookups re-shaped a paragraph. Every hit also
  removed and reinserted its entry and hashed a record holding two
  `TextStyle`s. Configurations are now interned once per footer build, a
  lookup hashes the string and an id, recency is a use counter, and the
  bound is 512. Per warm-back pass, measuring went from 50 and 56 ms to
  7 ms, and the taxonomy layout around it from 24 and 26 ms to about 1 ms.
- **Link routes.** `LinkTarget` resolved its URL to a local route on every
  build, only to decide whether its context menu offers a bookmark item. It
  now resolves when the menu opens. `_routeForLink` went from 8 and 12 ms
  per pass to 0.
- **Implicit animations.** Each inline metadata button and category link
  created an `AnimationController`, a `Ticker` and a `CurvedAnimation` twice,
  for `AnimatedContainer` and `AnimatedDefaultTextStyle`: 27 of each per
  row. `DImplicitTransition` animates identically but allocates them only
  when its value first changes. Scrolling 3,600 px of the widget-test list
  now allocates none of them, down from 720 of each.
- **Binding observers.** Every tooltip, hover card and popover registered
  its own `WidgetsBindingObserver`, about 21 per row. They now share one
  observer with constant-time registration. Scroll CPU did not change
  measurably (about 1 ms per pass before and after); the binding no longer
  calls hundreds of observers per metrics change.
- **Smaller costs.** Tooltips find their enclosing scrollables through
  `Scrollable.maybeOf` instead of walking every ancestor on each hover
  entry; the edge fade reuses its shader while its fades are unchanged; the
  metadata text style is derived once per theme; and the hover prefetcher
  ignores a row entering under the pointer during a scroll before it checks
  whether navigation shortcuts are allowed, which walked ancestors on each
  entry (1.1% of in-frame samples).
- **Item layers.** `DItem` kept an `Opacity` in its tree so that toggling
  `enabled` does not remount children, and Flutter's `RenderOpacity` is a
  repaint boundary with its own layer even when opaque. An enabled item now
  paints inline; only a dimmed one composites. With seven rows on screen the
  widget-test scene drops from 47 to 40 layers, one per row.

- **Inline buttons.** A row has about ten inline metadata buttons. Each
  wrapped its gesture detector in a `FocusableActionDetector`, whose hover
  and focus highlight bookkeeping it never used: a `GlobalKey`, a
  highlight-mode listener and a post-frame callback per mount, plus a
  second `MouseRegion`. The button now builds `Actions`, `Focus` and one
  `MouseRegion` itself, describes its focus in its own semantics node, and
  merges its icon theme and its surface's foreground colours without
  `Builder`s. Scrolling 3,600 px of the widget-test list creates 900 fewer
  elements for the first change alone (29,871 to 28,971) and 300 fewer
  render objects, states, global keys, listeners and callbacks; the
  semantics data is identical on macOS, iOS and Android.

- **Pages that bring new categories.** These were the slowest frames of a
  first pass, 4–10 ms against about 3 ms for the slowest row frames. When a
  page sideloads categories the site had not loaded, `prepareFeed` notifies
  the whole shell facade. In the desktop widget-test shell, that frame
  rebuilt 3,221 elements and marked 142 dirty; a page of known categories
  rebuilds 552 and marks 4. Three amplifiers are gone:
  - The filter bar's `DFitRow` fitted again from its first step on every
    rebuild. A row settled shortened was built at full length and then
    shortened again, and the view switch beside it moved views into its
    overflow menu and back, reparenting GlobalKey'd menus, popovers and
    focus nodes twice. `DFitRow` now takes a `watch`, as the mockup's
    FitRow does, and the filter bar watches what its shortened controls
    hide. A category list that grows off the path keeps the step, while
    room and width changes still fit the row again.
  - The view switch rebuilt its toggles, menus and measured copies (480
    elements) with unchanged inputs. It now returns its previous build.
  - The sidebar's category section was cleared on every merge, and its
    community header read the whole facade. The section is now kept while
    the categories it lists and their ancestors are equal, and the header
    selects only the forums it draws.

  That frame now rebuilds 1,530 elements and marks 16 dirty in the
  anonymous widget-test shell. For a signed-in reader whose sidebar lists
  its own categories, nothing under the sidebar or the view switch
  rebuilds, which `shell_rebuild_isolation_test.dart` pins. The rest is
  the list itself, the filter menus that receive the new categories and
  page scaffolding. Live, each first pass has one or two such frames
  among 2,270, mixed with the page's own row work, so three alternating
  runs per side could not separate them: 4.3, 5.5, 10.1 and 5.5 ms on the
  previous build, 4.6, 3.9, 6.0 and 8.5 ms after the `DFitRow` change.
  Steady scrolling was unchanged, as expected (warm pass in-frame CPU
  1,012–1,033 against 1,019–1,053 ms).

- **Links and items.** A row's category breadcrumb links and its `DItem`
  still used `FocusableActionDetector`, three per row, each registering a
  global key, a highlight-mode listener and a post-frame callback on mount.
  They now build its focus, cursor, shortcuts and actions themselves, and
  they listen to the highlight mode only while hovered or focused. Ten
  links or ten items mount ten fewer global keys, and their focus rings
  follow the highlight mode as before. This came after the final
  comparison. Over three alternating live runs each against the build
  before it, a row mounted three fewer elements (715 to 712 on the warm
  pass) and in-frame CPU did not move beyond noise (medians 1,030 and
  1,026 ms).

- **Count labels.** Each count a row writes resolved the message catalogue
  twice, matching the current locale against the supported ones, and built
  a `NumberFormat` for the integer: 3.2 ms and 1.5 ms per warm pass, about
  0.4% of in-frame CPU. The catalogue is now kept for the locale string it
  was resolved for, and one integer format per locale.

- **Smaller row costs.** Three lookups each row repeated as it scrolled in
  or out, per warm pass. Its keyboard-cursor lookup walked up to the list
  state on every build (2.2 ms); the list now passes the cursor down. A
  row leaving the list built its hover-prefetch key, which reads its
  reading policy out of plugin data, before checking whether anything was
  prefetched (1.9 ms). Boards resolved its scopes for topics on no board
  (1.2 ms). Together these are about 0.5% of in-frame CPU.

The CPU comparison at the top covers the first four changes; the final
comparison below covers all of them except the last three.

## Final comparison

The baseline (`d160c15d6`) and main with every change above (`76b99c013`)
alternated three times each on dev.discourse.org, in one session, while
the rest of the machine used 20–35% of one core. The screen was locked,
which keeps the CPU in a slower state, close to a slower machine's. Sample
counts compare like for like; raster times are not compared, because the
lock screen shares the GPU.

On the warm pass back up the list, 19,300 px and 2,400–2,600 frames per
run:

| Warm pass | Baseline | After |
| --- | ---: | ---: |
| Dart CPU inside frames, ms | 1,287 / 1,079 / 1,277 | 1,049 / 1,015 / 1,156 |
| Building, ms | 475 / 433 / 480 | 340 / 340 / 385 |
| Layout, ms | 480 / 431 / 483 | 394 / 376 / 426 |
| Frames over 8.33 ms of build | 58 / 63 / 57 | 26 / 25 / 34 |
| Build p99, ms | 9.9 / 11.4 / 9.9 | 8.4 / 8.4 / 8.7 |

By the medians, that is 18% less in-frame CPU, 29% less building and 18%
less layout, with fewer than half as many frames over budget. The timing
pass, run without sampling, went from 53, 33 and 44 frames over 8.33 ms to
20, 21 and 27, and from 1.22–1.29 ms to 1.14–1.21 ms mean build. On the
first pass down, paced by page loads, building fell from 79–82 to 61–62 ms
and layout from 178–193 to 125–160 ms.

The slowest frame of that first pass is the one in which a page brings
categories the site had not loaded. It took 5.4, 6.0 and 8.9 ms of build
in the baseline runs, and 1.8–3.5 ms after (2.3–3.7 ms in three more runs
of the same build).

What the app mounts does not depend on CPU state. At the end of each pass,
per topic row:

| Per topic row | Baseline | After |
| --- | ---: | ---: |
| Elements mounted | 695–763 | 665–736 |
| Render objects | 311–342 | 300–332 |

An earlier comparison of the row changes alone, before the new-category
work, measured 11% less in-frame CPU, 22% less building and 15% less
layout on the same pass.

The changes after this comparison (links and items, count labels and the
smaller row costs) were checked against it in two alternating runs each.
In-frame CPU per frame stayed within noise (0.44–0.46 ms before,
0.44 ms after) and rows mounted about five fewer elements (746 to 740 on
the warm pass). One run of each build still showed a single new-category
frame near 8 ms, so that frame varies widely from run to run.

## A false lead: scrolls that did not move the list

Two early runs looked like the list ignoring trackpad scrolls: up to 35 of
36 legs did not move it. Per-leg hit tests showed the gestures landing in a
tooltip popup open above the hovered row's metadata. The harness had parked
the mouse at the list's initial centre and sent trackpad pans at its
current centre, 24 px higher once the page header retracted. macOS delivers
a trackpad scroll at the cursor, so a user cannot reach that state; the
harness now pans where the mouse rests. Tooltips open only when hovered, as
the trace confirmed.

## Measurement

`integration_test/live_topic_list_scroll_profile_test.dart` boots the
production app, selects the site, opens Latest, maximizes the window, parks
the mouse over the list and sends one-second trackpad pans: twelve legs
down (`cold`, fetching pages), back up to the top (`warmBack`), and down
again without CPU sampling (`warmTiming`). Two census passes then count
every build, layout and paint block per frame through `FlutterTimeline`
collection, drained between legs so the VM's timeline buffer cannot drop
them. Each pass also records the requests made, the legs that did not move
the list and what the cursor hit instead, and the elements mounted at its
end.

The profile only scrolls. An `HttpOverrides` guard logs every request and
refuses writes other than the message bus's long poll, and topic loads,
which count a view. Runs refused hover prefetches and the restored reader
tab's topic load.

The CPU comparison above samples the UI isolate every 250 µs during `cold`
and `warmBack`. Sample counts measure the same scripted workload on both
sides and do not depend on display state. Frame timings do: the screen
locked partway through the session, and timing runs taken while the lock
screen's animated wallpaper shared the GPU doubled raster times on both
sides. Those timing runs are not used. The cold pass is paced by page
loads, so its CPU varies with the network; the warm passes repeat the same
rows.

## Remaining work

- A page that brings new categories still notifies the whole shell
  facade, because category data is read through it in about two dozen
  files. Category state on its own notifier would leave that frame to the
  list and the filter menus.
- On the raster thread, the edge-fade `ShaderMaskLayer`s remain the largest
  owner: an offscreen pass and blend per masked scrollable per frame. A
  replacement that leaves pixels unchanged still needs the backdrop under
  each fade to be one opaque colour.
- A row still mounts about 680 elements. Each inline button is about 40 of
  them and each tooltip about 10, most of them semantics, focus and
  overlay plumbing that a resting row never uses.
- The list's separators are list children of their own, so the separated
  delegate gives each one a `RepaintBoundary`, a keep-alive wrapper and an
  offset layer. With eight rows on screen, seven of the list's fifteen
  child boundaries are separators, and their offset and picture layers are
  14 of the widget-test scene's 43. `compositeFrame` takes about a
  quarter of in-frame CPU in the warm pass. Turning the delegate's
  boundaries off and keeping one per row was measured and made scrolling
  worse. Composite time fell 23 ms per warm pass, but the viewport's paint
  rose 113 ms, because it then re-records every separator in every
  scrolled frame: in-frame CPU 1,101–1,228 against 1,025–1,054 ms over
  three alternating runs each. Drawing the rule inside the row it follows
  would remove the layers without that repaint, but it changes the list's
  index mapping, extent estimation and keyboard selection.
- `super_sliver_list` 0.4.1 builds its `_log.fine` messages eagerly on
  every layout of the sliver, formatting six doubles each time: about
  5 ms per warm pass, 0.5% of in-frame CPU. That is for upstream to fix.
- Rows subscribe to the shell facade and their tab through `ShellSelector`
  and `ForumTabSelector`, and `ChangeNotifier.removeListener` scans every
  listener, so unmounting a row costs time proportional to everything
  else listening: about 10 ms per warm pass.

## Reproduce

Profile builds need the local signing tweak described in the
[desktop scrolling report](desktop-scrolling.md), and Homebrew's `rustc`
must not precede rustup's proxies on `PATH`.

```sh
flutter build macos --profile \
  -t integration_test/live_topic_list_scroll_profile_test.dart \
  --dart-define=PROFILE_LABEL=candidate
python3 tool/profile_desktop_scroll.py \
  build/macos/Build/Products/Profile/Discourse.app \
  --output /tmp/live-topic-list/run --trace none
```

To compare builds, alternate their runs and pass the output prefixes to
`tool/compare_desktop_scroll_profiles.py --baseline … --candidate …`. It
tabulates in-frame, build and layout CPU, frame times, rows' elements and
render objects and the other processes' CPU for every pass; the runner now
samples that background load, so runs that shared the machine can be
discarded.

`--dart-define=PROFILE_CPU=false` builds a timing-only harness;
`LIVE_CENSUS=false` skips the census passes; `LIVE_SITE` names another
saved forum. `--trace time` adds an Instruments Time Profiler recording of
every thread.

## Verification

- `test/topic_list_row_allocations_test.dart` scrolls a desktop list of
  realistic rows and fails on the baseline with 720 controllers.
- `test/implicit_transition_test.dart` compares `DImplicitTransition` with
  `AnimatedContainer` and `AnimatedDefaultTextStyle` frame by frame through
  a change, a retarget and a zero-duration change.
- `test/topic_text_measurements_test.dart` keeps its LRU tests and adds a
  bound measurer across clears and the configuration bound.
- `test/destination_bookmarks_ui_test.dart` finds a link menu's bookmark
  item on the menu's first frame.
- `test/d_scroll_behavior_test.dart` checks the fade keeps its shader in
  the middle of a list and replaces it at an edge.
- `test/overlay_observers_test.dart` covers forwarding and removal during
  dispatch.
- Tests that located the button surface through `AnimatedContainer` now
  find the `Container` the transition builds. Every other failure in the
  touched files also fails on `main`.
