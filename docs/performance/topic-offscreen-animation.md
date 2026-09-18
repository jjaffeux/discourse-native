# Retained topic GIF animation — September 18

Status: confirmed by widget tests and matched macOS profile comparison, reviewed
by the coordinating audit, and merged into local main at `ed84c313`.

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

[Final focused verification](topic-offscreen-animation/final-tests.txt) passes
all 243 selected tests, excluding only the three independently reproduced
baseline failures above. [Final full static analysis](topic-offscreen-animation/final-analysis.txt)
passes. Parent review independently checked all four accepted native files and
the production diff and accepted the bounded idle-work improvement.

## Accepted native comparison

`tool/topic_offscreen_animation_profile_main.dart` uses the same production
reader with 35 synthetic posts and a real looping GIF. It keeps semantics active,
requires resumed lifecycle at startup and throughout capture, and rejects any
inactive/background, semantics or viewport transition. A ten-second resumed
warmup precedes the capture. It scopes observations to `/uploads/test.gif`,
its descendant Image, and that Image's RawImage, validating the memory provider.

Four equal five-second phases cover visible, retained offscreen, reentry and
retention eviction. Each has 1500ms transition/decoder settling and an additional
1100ms timing-delivery drain. Only FrameTiming records with `vsyncStart` inside
the measurement interval count. Every sample and each phase boundary checks
mount/keep-alive/visible-range state; visible phases require image intersection.
Reports include image-frame changes, listener and scheduler states, individual
frame timings, lifecycle/semantics transitions, numeric rectangles, viewport and
DPR. Every phase checks unchanged numeric geometry through the timing drain. Any invalid phase rejects
the run. A frame identity observer owns only a temporary image handle and never
adds an image-stream listener.

The accepted baseline–fixed–fixed–baseline sequence ran on macOS 26.6.2 arm64,
Flutter 3.47.4 profile mode, at 1280 × 860 logical pixels and DPR 2, with the
exclusive desktop/CPU slot and no concurrent builds/tests. Each run used a
separate process, selected by exact bundle path in CUA and activated by clicking
its observed window container. All sixteen phases passed all guards, including
the drain. The same image element survived offscreen retention and reentry.

| Five-second phase | Baseline runs: image changes / idle frames | Fixed runs: image changes / idle frames |
| --- | --- | --- |
| Visible | 47 / 94; 47 / 94 | 47 / 95; 47 / 94 |
| Retained offscreen | 47 / 94; 47 / 94 | 0 / 0; 0 / 0 |
| Reentry | 47 / 94; 47 / 94 | 47 / 94; 47 / 94 |
| Evicted | 0 / 0; 0 / 0 | 0 / 0; 0 / 0 |

Both fixed offscreen phases had `mounted=true`, `keptAlive=true`, and no image
stream listeners. Baseline offscreen frame UI work totaled 24.05 / 21.95 ms and
raster work 174.28 / 171.00 ms; fixed offscreen frame work was zero. These are
sums of engine frame durations, not process CPU time or an energy measurement.
Each nominal five-second phase elapsed about 5.11 seconds due to timer delivery.

The [summary and source/collector metadata](topic-offscreen-animation/native-summary.json)
links the four raw runs by filename:
[baseline 1](topic-offscreen-animation/native-baseline-1.json),
[fixed 1](topic-offscreen-animation/native-fixed-1.json),
[fixed 2](topic-offscreen-animation/native-fixed-2.json),
[baseline 2](topic-offscreen-animation/native-baseline-2.json).
Each preserves all samples and selected frame arrays. A first
[exploratory baseline](topic-offscreen-animation/native-exploratory-baseline.json)
is excluded because profile mode stripped rectangle/size strings. The accepted
collector records numeric geometry instead.

An initial launch failed before creating a process (NSCocoa 256 → RBS 5 →
POSIX 163). Preserving the signed build's restricted identity/push entitlements
was incorrect for the isolated ad-hoc bundles. Both disposable copies were then
signed with the same [fresh review entitlements](topic-offscreen-animation/review-entitlements.plist),
retaining sandbox/debug/network capabilities and removing restricted push/team/
application-identity entries. Repository signing configuration was untouched.

Both isolated builds reside at `/tmp/topic-gif-profiles-35bf/baseline.app` and
`/tmp/topic-gif-profiles-35bf/fixed.app`, with distinct bundle identifiers.
[Baseline build](topic-offscreen-animation/build-baseline.txt) and
[fixed build](topic-offscreen-animation/build-fixed.txt) preserve the logs.
Reports initially land in each sandbox's `Data/tmp/topic-gif-{label}.json` and
must be copied before repeating that variant. All fixture processes were stopped
and the desktop lease released after capture.

The fixture isolates unnecessary idle work; a tiny synthetic GIF does not model
large-image decode cost, whole-process CPU, real-world scrolling performance or
mobile behavior. Native captures confirm removal of the specific idle workload;
they do not establish a general frame-rate or battery-life improvement.

## Main integration

Branch tip `4aec8cf3` merged into main `ebd76f84` from the main checkout under
the exclusive main lease, producing `ed84c313`. Existing HTML, code-block and
chat changes were preserved; the merge had no conflicts. The combined-main
[99-test focused run](topic-offscreen-animation/main-tests.txt) passed, including
both topic and chat GIF regressions, retained-content reuse, pagination,
selection and image behavior. [Full analysis](topic-offscreen-animation/main-analysis.txt)
passed with no issues. Native measurements apply to the unchanged topic
implementation; no extra native run was claimed for integration. No push.
