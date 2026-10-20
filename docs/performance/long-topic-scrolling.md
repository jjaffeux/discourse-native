# Long-topic scrolling investigation

Measured on October 20, 2026, against `main` at `f923bdb0f`.
The initial CPU profile used the earlier `1d0b1de1d` baseline.
The desktop investigation accepted no application optimization. Its workload did not reproduce
intermittent sluggishness, and the geometry-cache candidate did not establish a
reliable end-to-end improvement. The committed additions are profiling tools and
evidence for further investigation.

## Workload and limits

The native profile driver mounts the production `TopicView` and HTML renderer
with a 16,000-post stream and 200 loaded replies around post 6,070. Replies have
variable heights, quotes, links, inline code, Ruby code blocks, and lists. It warms
one 3,600-pixel round trip, then measures three frame-aligned round trips over
nine seconds. Each leg must actually move 3,600 pixels. The test also checks
return to the starting position, the complete loaded window, no Flutter
exceptions, and no page fetches.

The macOS viewport was 2,560 by 1,720 physical pixels at 2x density. One
untraced baseline at `1d0b1de1d` with CPU sampling enabled recorded mean build
time of 0.285 ms and mean raster time of 0.876 ms. No recorded build or raster
frame exceeded 8.33 ms. This is one CPU-sampled desktop profile. It does not
establish device FPS or explain intermittent stutter. Images, cold HTML construction, networking, the mobile sheet, and
physical iPhone performance are outside this workload.

## Rejected geometry cache

Each viewport inspection reads the same visible post bounds for navigation,
current-post context, and read receipts. A candidate cached bounds in a local
map for one synchronous inspection, including null results. It added 13 lines
and replaced five geometry calls. It retained no geometry between frames.

Five runs per side alternated the same two compiled macOS profile applications.
The existing opt-in diagnostics measured viewport inspection separately from
frame timing. VM sampling was disabled for these comparison runs. Every run
passed the workload assertions and recorded at least 1,084 inspections. The
reports retain all eight leg displacements, including the warm-up trip.

| Metric | Baseline median of run means | Candidate median of run means | Run-mean ranges, baseline; candidate |
| --- | ---: | ---: | --- |
| Viewport inspection | 33.84 us | 22.32 us | 18.74 to 40.06; 15.80 to 37.40 us |
| Frame build | 0.395 ms | 0.315 ms | 0.237 to 0.525; 0.220 to 0.513 ms |
| Frame raster | 1.377 ms | 1.021 ms | 0.787 to 1.639; 0.753 to 1.642 ms |

The inspection means favor caching in all five pairs, but their difference is
smaller than the full run-to-run variation. Frame metrics do not consistently
improve. The initial CPU profile also sampled substantial VM callback and
allocation work, so geometry was not established as the dominant steady-scroll
cost. The end-to-end timing verdict is inconclusive. The inspection difference
does not establish a remedy for the reported sluggishness. The candidate was
reverted. The raw numeric reports and compiled Dart framework hashes are in
[data/long-topic-scrolling.json](data/long-topic-scrolling.json).

## Loaded-window invalidation

`ShellTabContext._currentPostWindow` is cached against the site's Post store
generation. After a post update, `_loadedPostRange` searches from the stream's
beginning for a qualifying loaded post. The existing steady-snapshot regression
covers a window starting at post one and does not exercise this sparse late run.

The new focused benchmark keeps 200 posts near the end of a 2,000- or
16,000-post stream. Each sample changes a held post and resolves 200 snapshots.
All snapshots retain the expected complete window and resolve the saved
position. After warm-up, five debug samples of the 16,000-post case took
56.55 to 59.05 ms per 200 updates, with a median of 57.65 ms, about
0.288 ms per update. The final sample performed 3,208,400 Post reads. The
2,000-post case took 13.36 to 14.59 ms and 408,400 reads. These are debug
controller costs, not native scroll latency.

Two independent design sketches found that safe sparse indexing would add
retained-record queries or mutation tracking, stream indexes, and lifecycle
checks. Reusing only the previous range can select the wrong disjoint window
after a replacement or newly loaded post. Store reads also affect LRU order.
The measured cost did not justify adding that state without a device trace
showing it on the critical path. No window-selection change was made.

## Reproduce

Run the focused controller benchmark and snapshot regression:

```sh
TOPIC_WINDOW_BENCHMARK_OUTPUT=/tmp/topic-window.json flutter test --no-pub test/topic_window_update_performance_test.dart
flutter test --no-pub test/topic_viewport_snapshot_cost_test.dart
```

Run the native long-topic driver:

```sh
flutter drive --no-pub --profile -d macos \
  --driver integration_test/performance_driver.dart \
  --target integration_test/topic_long_scroll_performance_test.dart \
  --dart-define=PROFILE_LABEL=current
```

Add `--dart-define=TRACE_VIEWPORT=true` for inspection durations, or
`--dart-define=COLLECT_CPU=true` for a separate CPU profile. Tracing changes
absolute frame costs, so compare runs with the same flags. The controller
benchmark uses debug mode; the native driver uses profile mode.

For paired macOS comparisons, compile each revision with the same driver and
`TRACE_VIEWPORT=true`, then copy each complete
`build/macos/Build/Products/Profile/Discourse.app` to a separate directory.
The local run temporarily disabled signing in the worktree's Release xcconfig;
that setting was restored and is not part of the change.

```sh
python3 tool/benchmark_long_topic_scroll.py \
  --baseline /tmp/baseline.app --candidate /tmp/candidate.app \
  --output /tmp/topic-scroll-comparison
```

The runner checks successful workload completion, identical viewport size and
pixel ratio, loaded-window size, and all eight 3,600-pixel excursions. It alternates five runs per side,
records JSON and logs, and reports medians and ranges. It starts the supplied
benchmark applications and terminates only those child processes.

## Validation

Targeted Dart analysis and both controller benchmark tests pass. During the
rejected candidate's validation, 178 related context, reading, progress, churn,
rebuild, and header tests passed. One existing reflected-link hover test failed
at `topic_reading_integration_test.dart:3508` because its `InkWell` finder has no
match. Running that single test on unchanged `main` reproduced the same failure.
That desktop investigation changed no application source or appearance.

## iOS long-topic scroll follow-up

The mobile investigation found avoidable mounting work after a long post leaves
view. `ProgressiveHtmlMode` shared its frame budget between visible posts and
retained hidden posts, but fell back to a hidden post when no visible work
remained. A hidden post therefore kept constructing and laying out its tail
while the reader was elsewhere.

The queue now contains only visible unfinished bodies. Each body listens to its
ambient `TickerMode`, leaves the queue when hidden, and resumes from its existing
prefix when shown. The queue still grants one batch per frame across visible
bodies. Initial HTML parsing, initial prefix construction, and completed-body
edits keep their existing behavior. Paused completion futures settle on return
or disposal. Returning to an unfinished body now requires its remaining
progressive frames instead of relying on background completion. Already
completed bodies keep their full content.

The focused regression uses the production HTML renderer and a 450-paragraph
body. After disabling visibility and allowing that update to propagate, it
counts mounted paragraphs over six frames. Five alternating baseline/candidate
pairs all produced the same counts. The baseline mounted 192 additional
paragraphs, growing from 64 to 256. The candidate holds the count at 64, then
reaches all 450 when visible again and reuses the first paragraph element.
The run counts and measured/final source hashes are in
[the mounting work report](data/topic-hidden-html-mounting.json).
This counts eliminated hidden work. It does not measure FPS or scroll latency.

The actual `TopicView` regression jumps away from an unfinished long post to
post 41. Once the sliver's visibility update has propagated, the retained body
must keep the same paragraph count for six frames and the reading anchor must
stay within one pixel. Jumping back completes all paragraphs and preserves the
prefix element. The oversized-body recycling and saved-position cases remain
covered separately. A second regression drives the real mobile shell and topic
sheet through the same pause, jump-anchor, and return sequence.

All 45 focused widget tests and targeted analysis pass. All 45 reader geometry
cases also pass natively on the iPhone 18 Pro simulator. An initial native width
rebuild assertion failed once; the isolated case passed on unchanged main and
on the candidate, and the final complete native rerun passed.

An additional keyboard suite run passed 57 cases, including progressive long-post
paging and entry at the last page. Two other cases failed at
`keyboard_navigation_test.dart:165` and `:842`. Both short-post selection and
independent split-view selection failures reproduce identically on unchanged
main at `3c3d0d18e`.

Physical-device profiling could not start. Xcode has no signing account or
provisioning profile for the separate profiling bundle ID. No test app was
installed on the physical phone. Native iPhone simulator checks verify behavior
and rendering only. Device frame performance remains unmeasured.

Reproduce the behavior checks with:

```sh
flutter test --no-pub test/progressive_html_mode_test.dart test/progressive_html_visibility_test.dart test/topic_progressive_html_test.dart
flutter test --no-pub test/topic_offscreen_animation_test.dart test/topic_scroll_churn_test.dart test/topic_sheet_progressive_html_test.dart
flutter test --no-pub -d <ios-simulator-id> integration_test/topic_reader_geometry_test.dart
```
