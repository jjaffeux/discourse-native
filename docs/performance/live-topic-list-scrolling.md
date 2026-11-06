# Live topic-list scrolling (dev.discourse.org)

Scrolling the Latest list of a live forum costs **5–7% less UI-thread CPU
inside frames** after removing work that every row repeated as it mounted.
On the pass that mounts the most rows, scrolling 19,200 px back up the list,
two alternating runs per side measured, for the same rows, distance and
about 2,420 frames:

| Dart CPU in the pass | Baseline, ms | After, ms |
| --- | ---: | ---: |
| Inside frames | 1,127 / 1,144 | 1,068 / 1,064 |
| Building (`BuildOwner.buildScope`, including layout-time builds) | 418 / 435 | 347 / 327 |
| Layout (`PipelineOwner.flushLayout`) | 422 / 443 | 385 / 379 |

The largest app-level costs a row paid on mount are gone or cut by an
order of magnitude. The first pass down, which waits on page loads from the
forum, is paced by the network and did not change measurably.

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
  metadata text style is derived once per theme.
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

The CPU comparison at the top covers the first four changes; the final
comparison below counts all of them.

## Final comparison

What the app mounts does not depend on CPU speed or machine load. Across
ten live runs, five of each build, the rows mounted at the end of the
census passes measured:

| Per topic row | Baseline | After |
| --- | ---: | ---: |
| Elements mounted | 703–722 | 669–694 |
| Render objects | 316–323 | 302–312 |

A final CPU comparison of all the changes could not be measured cleanly:
other work on the machine kept 15 to 17 cores busy during most of those
runs, which changes both frame counts and sampling. The CPU table at the
top covers the first four changes and was taken while the machine was
otherwise idle; the later changes are evidenced by the counts here and by
the tests below.

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

- The slowest frames of the first pass (5–14 ms) are not rows. When a page
  brings categories the site had not loaded, `prepareFeed` notifies the
  whole shell facade, and the sidebar, page header, filter bar and plugin
  panels rebuild, including a `GlobalKey` subtree that is reactivated.
  Category state on its own notifier would leave those frames to the rows.
- On the raster thread, the edge-fade `ShaderMaskLayer`s remain the largest
  owner: an offscreen pass and blend per masked scrollable per frame. A
  replacement that leaves pixels unchanged still needs the backdrop under
  each fade to be one opaque colour.
- A row still mounts about 680 elements. Each inline button is about 40 of
  them and each tooltip about 10, most of them semantics, focus and
  overlay plumbing that a resting row never uses.

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
