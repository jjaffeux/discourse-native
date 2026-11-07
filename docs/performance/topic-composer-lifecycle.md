# Topic composer lifecycle performance

Measured November 7, 2026, against `30f6e213d`.

The composer retains foreground control painting during scrolling and reuses
unchanged retained editor widgets during presentation updates. Native controls,
editor state, focus, selection, undo and draft persistence keep their existing
owners.

## Changes

`ComposerPanel` places repaint boundaries around its desktop header, mobile
header controls and footer controls. The mobile gradient blur filters remain
outside the foreground boundaries, so they continue filtering the current
scrolling content.

Each presentation entry retains one `_ComposerSurface`. An immutable record
contains the effective minimized state, movement state, platform, placement,
editor size, mobile close-menu state and side-docking availability. Equal
records reuse the widget. The surface no longer reads mutable entry fields.
Inherited theme and localization changes still rebuild their dependents.

Visibility, focus exclusion, ticker state, overflow sizing and editor GlobalKeys
remain outside the cache. A Builder records the retained group's immediate
parent by Element identity. After removal, the same parent updates the existing
Stack and prunes the retired editor. A different parent resets the group key
before Flutter can reactivate the old subtree with disposed controllers.
Closing an inactive draft therefore retains the other editors while real
reparenting keeps its safety check. The desktop dock also removes a redundant
layout builder and its single-child expanded column.

## Deterministic work checks

`composer_chrome_scroll_performance_test.dart` drives four 24-point scroll steps
through a 120-paragraph topic draft and counts paint calls inside visible Native
buttons. The baseline paints those controls 432 times on desktop and 204 times
on mobile. The candidate paints them zero times. The candidate also passes with
a 336-point mobile keyboard inset. The test checks that scrolling actually moves
and preserves the document.

`composer_draft_tabs_virtualization_test.dart` opens a fourth draft while two
other editors remain inactive. The baseline rebuilds both inactive editors; the
candidate rebuilds neither. The same test changes the theme, closes the new
draft, checks surviving editor state and selection, then edits and undoes text.

Closing an inactive draft among three mounted editors previously rebuilt both
survivors on desktop and mobile. The candidate rebuilds neither. Additional
regressions combine closing with a fullscreen transition and promote a surviving
mobile editor. Removing the reparent safeguard entirely fails the combined
close/fullscreen case with disposed Markdown controller and focus-node errors;
the parent-identity check passes it.

The keyboard-close control fixture now opens its editor through the shell. Its
previous standalone editor was not a registry member, so both keyboard-close
tests failed on the baseline before reaching a discard dialog.

## Native fixture

`integration_test/composer_lifecycle_performance_test.dart` uses the production
shell with fake services, 250 categories and tags enabled. It opens a topic
composer, inserts 120 paragraphs, scrolls 1,800 points in each direction and
saves and closes the draft. Assertions check the visible composer, scroll
destination, unchanged source, successful close result and registry removal.

Runtime environment variables configure macOS captures:

| Variable | Meaning |
| --- | --- |
| `PROFILE_LABEL` | Capture label. |
| `COMPOSER_MOBILE=1` | Phone dimensions and iOS theme on the host renderer. |
| `COMPOSER_RETAINED_DRAFTS=6` | Keep six long drafts mounted before measurement. |
| `COMPOSER_CLOSE_INACTIVE=1` | Save and close an inactive draft while keeping the current editor visible; requires retained drafts. |
| `COMPOSER_ITERATIONS=1` | Number of lifecycle repetitions; defaults to six. |
| `PROFILE_COMPOSER_WIDGETS=1` | Separate diagnostic timeline with build, layout and paint instrumentation. |

For example:

```sh
PROFILE_LABEL=candidate COMPOSER_RETAINED_DRAFTS=6 \
flutter drive --no-pub --profile -d macos \
  --driver integration_test/performance_driver.dart \
  --target integration_test/composer_lifecycle_performance_test.dart
```

Local unsigned builds use a temporary `XCODE_XCCONFIG_FILE` with
`CODE_SIGNING_ALLOWED = NO`, `CODE_SIGNING_REQUIRED = NO`, `ARCHS = arm64`
and `ONLY_ACTIVE_ARCH = YES`. Application signing settings remain unchanged.
Preserved bundles can be repeated with `--use-application-binary=<bundle.app>`.
The driver writes `build/integration_response_data.json`.

The timing window contains the action and Flutter settling, excludes frame-batch
delivery waits, and filters frames by their build-start timestamps. Elapsed time
includes test pumps, animations and vsync. Mobile host runs use mocked text input
and do not measure an OS keyboard, device raster performance or physical input
latency.

The native host reported near-zero raster spans even after dismissing its native
launch screen and activating the window. Raster results are unusable. UI-thread
frame work and deterministic work counts are reported separately; neither
establishes a device frame-rate improvement.

## Timing comparison

The surface-cache and paint-boundary comparison alternates five fresh profile
processes per side for each layout. Desktop keeps six long drafts mounted;
mobile keeps none. The host has 18 logical CPUs, with recorded load averages
between 1.48 and 2.23 during the comparison. No builds or other test runs overlap
the measured processes. Instrumented diagnostic captures are excluded.

The largest UI frame during desktop opening falls from a median of 59.08 ms
(range 56.21 to 63.63) to 22.60 ms (20.88 to 29.94). Retained editor rebuilding
is the observed limiter addressed by the cache. Total UI frame work during
opening falls from 68.60 ms to 33.94 ms. Settled action time stays around 218 ms,
including test pumps and animations; this is not an input-latency result.

Scrolling avoids the control paint calls shown above. Frame timing changes are
small relative to run variation. Visible-editor closing has no measurable timing
improvement in that comparison. The later parent-identity optimization addresses
inactive closing separately, as established by the survivor rebuild regression.

Raw native results, diagnostic timelines and the per-run comparison summary are
retained in `/tmp/composer-performance/`. The primary comparison summary is
`comparison-summary.json`, with five JSON captures for each layout and side.

The final implementation also passes native save-and-close runs for inactive
drafts on both layouts, preserving the currently visible editor. Those final
captures are `final-inactive-desktop.json` and `final-inactive-mobile.json`.

Focused verification passes for composer opening, docking, close safety,
retained draft tabs, static control painting, embedded scrolling, panel controls
and mobile sheets. Static analysis reports no issues in the six changed Dart
files. The full test suite is left to CI, per the project instructions.
