# Topic-list header scrolling — September 20, 2026

The retracting page header changes the viewport height on every animation
frame. `DPageReadingLane` previously rebuilt its child on those height changes,
replacing the topic-list sliver delegate and invoking builders for retained
rows. The row-content cache prevented most full subtree rebuilds, but not the
delegate and selection-wrapper updates.

The lane now retains its child while width, reserved insets and the content-width
policy stay equal. Normal layout still receives each new height. Replacing the
lane widget resets the cache, and the existing inner `Builder` continues to
track the caller's inherited dependencies. There are no changes to header
animation, controls, row content, scroll physics or offscreen retention.

## Deterministic regression

The production topic list is mounted beneath a 104px retracting `DPageSurface`
header. Four alternating 40px scrolls each allow the animation to finish.

| Work | Baseline | Fixed |
| --- | ---: | ---: |
| Row-builder calls | 368 | 4 |
| Repeated row indices within each animation | 338 | 0 |
| Full row-subtree builds | 4 | 4 |
| Row layouts recorded by the capture | 4 | 4 |

The regression fails on the baseline and passes with the change. It also
checks the scroll offset and viewport height after every animation. Separate
tests preserve entered input and element identity across height and width
changes, and verify updates from inherited direction and replacement builders.

## Native measurement

The offline production-widget fixture uses 1,000 local topics, parent/category
breadcrumbs, two tags, last-poster avatars without network images and a 104px
header. Measurements use macOS debug mode, the installed Flutter 3.47.4 / Dart
3.13.3, an 800px-wide fixture with a 600px total height, and accessibility off.
Baseline source is `631ad25c6` with the same fixture instrumentation.

Three alternating baseline/fixed runs reproduce the eliminated builder work.
These values are the median of each run's topic-active frame UI p95; they are
not release performance claims.

| Phase | Baseline p95 | Fixed p95 | Baseline builder calls | Fixed builder calls |
| --- | ---: | ---: | ---: | ---: |
| Steady: 180 × 40px | 15.70ms | 15.13ms | 271–287 | 92 |
| Fast: 40 × 1,200px | 42.27ms | 41.51ms | 349 | 349 |
| Return: 40 × −1,200px | 30.13ms | 32.41ms | 349–357 | 306–307 |

The broad workload does not establish a consistent frame-time speedup. Fast
scrolling still constructs a viewport of new cards per step. Those full mounts
remain expensive in debug mode, and the original CPU capture prominently
contains Flutter debug tree checks. No further change to controls or retention
was justified by these results.

The separate header phase (one matched pair, eight alternating 40px scrolls)
isolates the improvement more clearly. Use **all** captured frames here: once
retained-row work disappears, most header-animation frames no longer have a
topic event and would be omitted by the topic-active frame subset.

| Header phase | Baseline | Fixed |
| --- | ---: | ---: |
| Captured frames | 264 | 265 |
| UI p50 | 1.909ms | 0.987ms |
| UI p95 | 3.311ms | 1.450ms |
| Total measured UI work | 505.511ms | 297.159ms |
| Row-builder calls | 2,868 | 12 |
| Full row-subtree builds | 12 | 12 |
| UI frames over 8.33ms | 1 | 0 |

Header-phase UI p95 decreased by 56%; this describes that debug fixture phase,
not overall scrolling performance. Per-run counters and timing summaries are
recorded in [topic-list-header-scrolling.json](topic-list-header-scrolling.json).

A profile build was attempted but the installed SDK's AOT snapshot generator
aborted on `_Rect` in `package:flutter/src/widgets/_window_macos.dart`
(`Class with illegal cid, full-aot`, exit −6), before this production change.
The repository SDK pin and dependencies were not changed to work around it.

Reproduce with the existing runner, using `--debug` if that SDK profile failure
persists:

```sh
flutter run --profile -d macos -t tool/topic_list_scroll_profile_main.dart \
  --dart-define=LIST_MODE=card --dart-define=LIST_EVENTS=false \
  --dart-define=LIST_ASSIGNMENTS=false --dart-define=LIST_HEADER=true
```

`LIST_HEADER` adds a final phase of eight small alternating scrolls separated
by 250ms so header animation can be measured separately from rapid row mounting.
`SCROLL_HEIGHT` controls the fixture height, defaulting to 600px.

## Verification

- Full `dart analyze`: no issues.
- 112 focused tests passed across reading-lane geometry/integration, page-surface
  behavior, topic-list scrolling/lifecycle and navigation.
- Formatting and `git diff --check` passed.
- Native light-theme inspection confirmed unchanged card appearance, independent
  category/tag links and sort actions in the accessibility tree. Wheel scrolling
  retracted the header, and reverse scrolling revealed it again.
- Native measurements use isolated, locally signed debug fixtures with no
  account data. This is macOS verification; platform overrides in widget tests
  are not iOS or Android device testing.
