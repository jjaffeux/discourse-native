# Retained chat animation work

The production chat stream retains up to 24 recently mounted rows for local
scroll reversals. Before this change, its visibility callback changed only
keyboard focus eligibility. A retained `ChatMessageTile` containing `SiteImage`
therefore left Flutter's animated `Image` listener active offscreen.

The fix puts the existing `TickerMode` primitive around the retained row's
unchanged child. Only visibility transitions update the boundary; scrolling
within the same visible range does not set state. Retention capacity, eviction,
message subscriptions, focus policy, semantics and playback controls are
unchanged. An ancestor disabled ticker mode still wins, and the image's own
`MediaQuery.disableAnimations` pause preference remains independent.

## Workload and measurement

`test/chat_retained_animation_test.dart` mounts the real `ChatChannelView`,
`ChatMessageTile`, HTML renderer and `SiteImage`, using an offline repository
serving three distinct copies of a tiny looping two-frame GIF (100 ms/frame).
The remaining 97 messages contain ordinary text. Eight 150-pixel scroll steps
move the GIF rows offscreen within the retention window; the reverse steps
revisit the same elements. A final long jump evicts them.

The unchanged production baseline at `552e9a729180e010054183edd0a5a306f3b565bc`
rebuilt the tracked `Image` 10 times in ten 110-ms steps both while visible and
while offscreen with sliver `keptAlive == true`. Its effective ticker mode
remained enabled. The regression failed the expected zero-offscreen-build
assertion before the production fix.

`tool/chat_retained_animation_profile_main.dart` runs the same production
fixture natively in profile mode. Each idle sample lasts three seconds after
a one-second grace period. It records existing completers' `hasListeners`,
delivered image-frame identity changes, scheduler frames, UI frame count and
aggregate UI build time. Timing samples use exact `Timeline.now` start/end
bounds, wait 1100 ms for batched timing delivery, and retain only frames whose
vsync timestamp falls inside the interval. The raw selected vsync, build and
raster arrays are saved. Scheduler callbacks and active image listeners remain
the primary measures of idle work.

The collector targets only message IDs 98–100 and their known GIF `SiteImage`
descendants, requires exactly three `Image`s with multi-frame completers, and
requires a decoded `RawImage` for each mounted target. It seeds image identities
at every phase's start, so initial observations and scrolling/grace-period
changes are not counted. At both sample endpoints it rejects a phase unless all
three original rows/images are mounted and visible, mounted and retained, or
fully evicted as appropriate. Re-entry therefore requires the original elements.
The observer adds no image listeners and schedules no frames itself. It tracks the original visible rows through retention, re-entry
and eviction. It waits for a resumed app lifecycle before starting and marks
a sample invalid if a lifecycle observer sees the app leave the foreground.
Image identity observations are delivered frames, not direct
codec-call instrumentation; an already in-flight decode may finish when the
last listener is removed.

## Deterministic verification

After the fix, the same ten measured steps produce 10 visible image rebuilds
and zero retained-offscreen rebuilds. The offscreen image has no stream
listener, effective ticker mode is disabled, and the binding reports zero
transient callbacks and no scheduled frame after the grace period.

The regression also checks retained element identity, effective focus ancestry,
three-row visible/retained/re-entry/eviction phase gates, re-entry animation,
ancestor tab suspension, explicit user pause surviving a
local reversal, explicit resume, and final eviction/disposal. A test-only focus
assertion was corrected to inspect ancestor focus restrictions rather than a
nested HTML focus node's own flag.

Verification completed:

- `flutter test --no-pub test/chat_retained_animation_test.dart`: passed.
- `flutter test --no-pub test/chat_scroll_performance_test.dart
  test/site_image_test.dart test/chat_channel_view_lifecycle_test.dart`: all
  78 other cases passed in the combined run. This includes live reaction updates,
  bounded retention, channel lifecycle behavior, and all six ordinary-scroll
  variants reporting `messageRebuilds: 0`.
- Focused `flutter analyze --no-pub` on the production file, regression,
  shared fixture, and native profile entry point: no issues.
- Baseline and after macOS profile builds completed. Isolated copies were
  ad-hoc signed with restricted push/team/application-identity entitlements
  removed; required debug capabilities were preserved. Static signature
  verification alone does not establish successful native execution.

Native execution is pending: the shared desktop was locked during this audit,
and the coordinator paused native captures until the user unlocks it. No native
result or timing improvement is claimed, and no merge has been performed.

## Scope and limits

The installed SDK used for this comparison is Flutter 3.47.4 / Dart 3.13.3.
The repository's Flutter 3.47.2 pin is unchanged. Widget-test timing uses a
controlled clock plus real asynchronous image decoding; it is not native CPU,
GPU, energy or display timing. The native fixture uses local tiny GIFs, not
network or large-media throughput. WebP and platform video/audio playback are
not directly measured.

Source inspection found a similar absence of a visibility ticker boundary in
`_TopicPostItem` retention. That is a separate, unmeasured candidate; this change
does not modify topic retention.
