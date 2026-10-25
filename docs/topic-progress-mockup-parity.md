> Historical design and capture notes. The app now uses the [flat appearance](material-mockup-parity.md); earlier glass and depth measurements describe the retired rendering.

# Topic progress panel parity

Reference: `discourse-native-mockups` at `070b91a`, `TimelineMenu`,
`.timeline-scrub`, and `.menu-sheet`, plus the October 14 desktop/phone captures.

The progress trigger uses the 26px floating preset on desktop and the 30px
footer preset on phones. Both retain the shared raised tint, rim, blur and
shadow in Liquid Glass, matching the mockup's `menu-row glass` trigger.
Standard keeps the desktop's thin blurred well and the phone's clear surface.
The Native preset owns the artwork and matching hit bounds.

Desktop uses the Native timeline popover at 300px wide with a 16px radius and
14px padding. Its selected post shows a 32px Native avatar, username, creation
date and tabular position count. The timeline has a 6px accent track and a white
20px thumb within a 22px control. Both ends show their dates above equal-width,
34px filled Native arrow buttons. The selected end is disabled; failed lookups
can still retry. Large accessibility text stacks the buttons and wraps dates.

Phones use a route-owned Native bottom Sheet. The shared `DSheetVariant.menu`
preset supplies its 36 by 5px grab handle, 22px top/24px bottom corners,
6px side/bottom gap and bottom safe-area exclusion. Downward swipes start on
the sheet or the empty backdrop above it. It supports short-swipe restoration,
outside dismissal, Back and Escape. Horizontal timeline input remains independent
of sheet dismissal. Existing sheet presets keep
their original geometry.

The editor retains its opening account/site/topic/tab lease. A drag previews
loaded author/date metadata, falling back to Post N for unloaded positions.
Releasing the slider or tapping First post/Latest post commits navigation and
closes the phone sheet immediately while an unloaded post resolves. Cancellation
restores the preview and leaves it open.
Late lookups cannot mutate a replacement route or a reopened panel. Topic API
creation/latest timestamps remain available when endpoint posts are unloaded.

Focused checks cover both themes and materials, desktop/phone, RTL, enlarged
text, API timestamps, slider/control bounds, swipe/reopen and navigation leases.
`TOPIC_PROGRESS_CAPTURE_DIR` on `topic_progress_lifecycle_test.dart` saves the
rendered matrix. `lib/topic_progress_review_main.dart` is the offline desktop
fixture using the same production panel and Native components.
