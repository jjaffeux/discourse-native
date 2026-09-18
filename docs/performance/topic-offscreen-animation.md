# Retained topic GIF animation — September 18

Status: confirmed in widget tests; native profile comparison pending an unlocked
Mac and the coordinating audit's exclusive capture slot. Not merged. No native
performance reduction or mobile result is claimed yet.

The baseline is `552e9a729180e010054183edd0a5a306f3b565bc`. The installed SDK is
Flutter 3.47.4 (`9584c6713b`), Dart 3.13.3. The repository SDK pin is unchanged.

## Confirmed issue and change

`TopicView` retains up to 24 post trees, including three large posts, within a
262,144 HTML-character budget. `CookedHtml` creates `SiteImage`, which renders
an actual animated image stream. Tab-level `TickerMode` suspends images for
inactive tabs, but retained offscreen posts in an active tab lacked that gate.

The reproduction decodes a looping two-frame GIF through the actual topic
reader, with no substitute image widget or stream. After moving the first
post into sliver keep-alive storage, its image element remains mounted,
`keptAlive` is true, and its existing stream still has listeners. Decoded image-frame
identity changes and the test scheduler remains active while it is offscreen.
The probe resolves the existing stream without adding a listener.

The topic now projects the laid-out sliver's visible raw indices onto post IDs,
accounting for separated-list indices and the earlier-page header. A frame-safe
notifier changes only when that set changes. Each retained post wraps its stable
content child in Flutter `TickerMode`; this releases the existing image listener
without disposing HTML, selection ownership, or live post subscriptions. The
existing parent tab mode still applies. Partially visible posts remain active;
this is intentionally post-level visibility, not per-image occlusion tracking.
No public Native component API or chat implementation changes are involved.

## Widget evidence

[Original failure](topic-offscreen-animation/widget-baseline-failure.txt) and
[baseline frame probe](topic-offscreen-animation/widget-baseline-probe.txt)
cover both topic layouts. The probe uses the
[original fixture](topic-offscreen-animation/widget-baseline-fixture.dart.txt),
with offscreen listener/frame expectations reversed and diagnostic prints.

[Four fixed regressions](topic-offscreen-animation/widget-fixed.txt) cover:

- Both layouts, actual GIF frame advancement, retained offscreen listener
  removal and stable frame, same-element reentry, partial visibility and eviction.
- Earlier-page header presence, pending loading and final prepend removing the
  header, checked against actual row parent-data indices and the visible range.
- Tab suspension/resumption, user pause state and global animation preference.
- Offscreen likes and cooked-body edits, including animated replacement media.

The [broader run](topic-offscreen-animation/focused-tests.txt) passes 243 tests,
including retained-content reuse, no held-content rebuilds during paging,
selection, scrolling, lifecycle, reading geometry and keyboard behavior. Two
390px keyboard topic-list visibility assertions fail; [baseline reproduction](topic-offscreen-animation/keyboard-narrow-baseline.txt)
confirms both failures. One other keyboard scrolling assertion was excluded
from that run after independently reproducing its identical failure on baseline
(expected offset greater than 2684.5, actual 2598.5):
[keyboard baseline](topic-offscreen-animation/keyboard-baseline.txt).
No unrelated keyboard code was changed.

[Full static analysis](topic-offscreen-animation/analysis.txt) passes.

## Pending native comparison

`tool/topic_offscreen_animation_profile_main.dart` uses the same production
reader with 35 synthetic posts and a real looping GIF. It keeps semantics active,
requires resumed lifecycle at startup and throughout capture, and rejects any
inactive/background transition. It scopes observations to `/uploads/test.gif`,
its descendant Image, and that Image's RawImage, validating the memory provider.

Four equal five-second phases cover visible, retained offscreen, reentry and
retention eviction. Each has 1500ms transition/decoder settling and an additional
1100ms timing-delivery drain. Only FrameTiming records with `vsyncStart` inside
the measurement interval count. Every sample and each phase boundary checks
mount/keep-alive/visible-range state; visible phases require image intersection.
Reports include image-frame changes, listener and scheduler states, individual
frame timings, lifecycle transitions, viewport and DPR. Any invalid phase rejects
the run. A frame identity observer owns only a temporary image handle and never
adds an image-stream listener.

The fixture isolates unnecessary idle work; a tiny synthetic GIF does not model
large-image decode cost, real-world scrolling performance or mobile behavior.
Native acceptance and the parent audit's review/merge slot remain required.

Both isolated macOS profile builds completed without launching:
`/tmp/topic-gif-profiles-35bf/baseline.app` and
`/tmp/topic-gif-profiles-35bf/fixed.app`. They have distinct bundle identifiers
and verified ad-hoc signatures. [Baseline build](topic-offscreen-animation/build-baseline.txt)
and [fixed build](topic-offscreen-animation/build-fixed.txt) preserve the logs.
The planned two-pair comparison needs roughly three minutes of capture plus
launch/inspection overhead. Neither bundle has been run yet.
