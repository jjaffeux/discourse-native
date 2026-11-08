# Topic composer lifecycle performance

Historical comparison measured November 7, 2026, against `30f6e213d`.
The November 8 verification below has not established the 120 Hz target.

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
| `COMPOSER_MOBILE=1` | Phone layout and iOS theme on the host renderer; native view dimensions remain unchanged. This is a diagnostic simulation, not mobile-device evidence. |
| `COMPOSER_RETAINED_DRAFTS=6` | Keep six long drafts mounted before measurement. |
| `COMPOSER_CLOSE_INACTIVE=1` | Save and close an inactive draft while keeping the current editor visible; requires retained drafts. |
| `COMPOSER_ITERATIONS=1` | Number of lifecycle repetitions; defaults to six. |
| `PROFILE_COMPOSER_WIDGETS=1` | Separate diagnostic timeline with build, layout and paint instrumentation. |
| `PROFILE_COMPOSER_CPU=1` | Separate sampled CPU capture for each action; excluded from timing comparisons. |

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

The earlier native host captures reported near-zero raster spans even after dismissing its native
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

## Deferred block action validation

A second pass compares against `ddeb58520`. A separate CPU capture finds
22 of 299 closing samples under `_handle → move → _validatedMove`, including
16 regex-containing stacks. The two block-menu enabled checks each construct
and parse a hypothetical reordered draft, even while their menu is closed.
Opening also samples that validation path. Scrolling does not; its largest
sampled stack is paragraph painting.

The existing Native menu now mounts each move row through a `Builder`. Enabled
state and the block's position are resolved from the current index when the row
mounts. Actual moves retain the same semantic validation. The change adds no
menu API, state cache or alternative control. The new keyboard regression
checks the disabled boundary action and activates the first enabled action.

The candidate CPU capture has no samples in block-move validation during
opening, scrolling or closing. These are sampled work observations, not a
latency measurement. The directly related block suites pass 151 tests and
static analysis reports no issues in the three changed Dart files.

The CPU option stores samples and only the functions present in sampled stacks.
Each function retains its original VM function-table `index`, which identifies
entries in sample stacks. This avoids exporting tens of thousands of unused
native symbols. Captures and comparisons for this pass are retained in
`/tmp/composer-performance-round-two/`.

The frame-timing result is inconclusive. The first five alternating processes
per side report total closing UI work medians of 100.19 ms before and 89.31 ms
after, with overlapping ranges of 92.28 to 107.93 ms and 88.47 to 107.75 ms.
The largest closing frame does not measurably improve. Five more pairs reverse
the build order; those remain variable, and one baseline closing action is
interrupted for 32.69 seconds. That entire pair is excluded from the final
summary, using interruption limits of two seconds for opening/closing and four
seconds for the fixed two-second scroll. All raw captures remain available.

Two existing Brigantine processes consume roughly 250% CPU each during the
repeat pass. They remain running. No additional opening, scrolling, closing
latency or frame-rate speedup is claimed from these timings. This pass establishes
removal of unused desktop block-menu parsing while preserving move behavior.
The final CPU capture also verifies exact coverage of all sample stack indices
in its exported function table.

## November 8: native 120 Hz verification

The target is every measured UI and raster-thread frame at or below
`1000 / 120 = 8.333333 ms`, with at least five independent paired launches per
comparison. Each launch includes a first and a repeated opening. Final checks
also need resumed long drafts and retained editors. FrameTiming raster duration
is raster-thread work; it does not measure GPU completion or display presentation.

The earlier zero-raster problem came from overriding the Flutter test view's
physical size and pixel ratio while its native surface retained different
constraints. The engine discarded those layer trees. The current fixture uses
the native view without overrides and rejects phases without meaningful raster
work. It records native pixel ratio, refresh rate, exact phase timestamps and
individual frame numbers/timings.

The fixture uses Flutter's public `LiveWidgetController` with the integration
binding's test error zone. Native text input stays connected, and phone scrolling
keeps the actual keyboard visible. Opening and closing include bounded waits for
stable native keyboard insets. Accessibility follows the OS. Its leak invariant
accounts for the single semantics handle owned by the platform while still
rejecting application-owned leaks. Application cleanup and its invariant checks
must finish before the completion marker is published.

The runner writes each driver response into a fresh temporary directory, checks
its completion, workload, iteration set and compiled label, and preserves failed
captures separately. On macOS it observes and activates the exact profiling PID,
avoiding another running application with the same bundle identifier. The budget
checker rejects debug/instrumented data, simulated layouts, missing native input,
wrong workloads, copied phase windows, insufficient repetitions and scrolling
captures throttled below the expected native cadence.

Build a profile bundle for
`integration_test/composer_lifecycle_performance_test.dart`. Physical iPhone
settings use `--dart-define`; the device launcher does not forward arbitrary
shell environment variables. For example:

```sh
flutter build ios --no-pub --profile \
  --target integration_test/composer_lifecycle_performance_test.dart \
  --dart-define=COMPOSER_ITERATIONS=2 \
  --dart-define=PROFILE_LABEL=baseline
ditto build/ios/iphoneos/Runner.app /tmp/baseline.app

python3 tool/profile_composer_lifecycle.py /tmp/baseline.app /tmp/baseline-0 \
  --device DEVICE_UDID --iterations 2 --label baseline

python3 tool/check_composer_frame_budget.py /tmp/baseline-0.json \
  --platform iOS --repetitions 1
```

This calibrates one launch. Acceptance requires five launches per side,
alternating baseline and candidate. Pass only their capture filenames to the
checker, excluding failed or visibility reports. `COMPOSER_RESUME_DRAFT=1` opens a saved
120-paragraph draft inside the opening window. The runner/checker select that
workload with `--opening resumed`. Retained-draft runs use
`COMPOSER_RETAINED_DRAFTS=6` and `--retained-drafts 6`; inactive closing also uses
`COMPOSER_CLOSE_INACTIVE=1` and `--inactive-close`.

A successful unchanged-application calibration against `634e5e50f` on the physical iPhone 15 Pro Max
reports 430 by 932 logical pixels, DPR 3 and 120 Hz, with real input and native
accessibility enabled. This is one process with two lifecycles, not acceptance
or a before/after comparison:

| Phase | Largest UI frame | Largest raster-thread frame |
| --- | ---: | ---: |
| Opening | 16.357 ms | 6.314 ms |
| Scrolling | 12.824 ms | 3.329 ms |
| Closing | 17.631 ms | 1.171 ms |

The conditional todo-span invalidation attempt alone was rejected. Five
alternating desktop launches per side changed the median largest closing UI
frame from 16.111 ms (15.000–16.492) to 15.770 ms (9.568–16.400), within run
variation. A mounted autosave probe then demonstrated another invalidation:
the localized ThemeData objects differ in identity while their values, editor,
source, selection, size and strut remain equal. Flutter's localized-theme cache
has only five identity-keyed entries.

Two candidates are prepared and have passed focused correctness checks:

- Preserve spans across value-equal theme recreation, and avoid invalidating
  plain-document spans when their todo read-only flag changes. Actual theme
  changes and todo callback transitions remain covered.
- Let Native DInput skip unsupported Apple Pencil geometry on confirmed
  iPhones. Its cached native model query preserves iPad, unknown/error, Android
  and web behavior. The first native lookup must remain represented in cold
  opening or startup evidence.

A separate physical-phone CPU diagnostic attributes 859 rectangle-query samples
to Flutter's iOS handwriting update path. The diagnostic is instrumented and
excluded from timing acceptance. It does not establish an opening or closing
speedup.

At the current checkpoint, the task branch has been rebased onto `f00de6dc2`;
191 focused tests pass and static analysis is clean. The preserved profile
bundles predate that rebase and must be rebuilt for final paired verification.
Candidate timing acceptance remains blocked: the iPhone disconnected, and macOS
keeps loginwindow in front of the profiling process. Locked-screen captures are
excluded. No new optimization has been accepted or merged from this verification
pass. Raw captures, diagnostic profiles and the decision log are retained in
`/tmp/composer-120fps/` and the ignored `.audit/composer-120fps.tsv`.
