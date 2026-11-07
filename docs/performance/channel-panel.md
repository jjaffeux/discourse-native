# Channel panel painting

The channel, transcript, and composer have separate repaint boundaries.
Sheet movement can reuse the channel's painted layer. Transcript scrolling
does not repaint the idle composer. During entrance, the header and dock can
animate without repainting the transcript's surrounding widgets.

The layers contain live widgets. Messages, selections, focus, and composer
input continue to update normally. The existing virtualized list and bounded
message retention still own how much history stays mounted.

## Rendering checks

Compared with `138afd4e3` on November 7, 2026, with the real application shell, 80 formatted
messages, a 1440 × 900 desktop layout, and 390 × 844 phone layouts. The test
uses macOS, iOS, and Android platform variants in Flutter's widget renderer.
No external network requests are needed.

These are render-object paint calls, not milliseconds or GPU frame times.
Five runs per side alternate the original implementation and the change.
Each row reports the median; the minimum and maximum equal the median in
these deterministic runs.

| Scenario | Original | Change |
| --- | ---: | ---: |
| Desktop scroll, 12 frames | 653 | 598 |
| iOS scroll, 12 frames | 678 | 568 |
| Android scroll, 12 frames | 704 | 594 |
| Phone sheet drag, 12 frames, either platform | 2,476 | 1,084 |
| Phone entrance after reopening, 16 frames, either platform | 2,632 | 2,035 |
| iOS swipe dismissal after release | 2,590 | 1,459 |
| Android swipe dismissal after release | 2,600 | 1,469 |

The work removed is repeated painting of unchanged widgets. The idle
composer receives zero paint calls during the scroll. The channel receives
zero during the measured drag and dismissal. Header, dock, scrollbar, and
fade animation work remains where its appearance changes. These counts do
not establish a device frame-rate improvement or a cold network load time.

`test/channel_panel_performance_test.dart` verifies actual scrolling and
sheet movement, retained message artwork during entrance, cancellation back
to the original sheet position, dismissal, and a visible live message edit.
Its `CHANNEL_PAINT` lines print the counts above. Run it with:

```sh
flutter test test/channel_panel_performance_test.dart --reporter expanded
```

Channel lifecycle, existing scrolling, mobile sheet, composer, and mobile
title-return tests also validate the change.
