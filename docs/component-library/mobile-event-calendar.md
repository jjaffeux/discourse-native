# Mobile upcoming-event calendars

Implemented against the two user-supplied September 23, 2026 screenshots:
compact Month with colored bars and overflow counts, and Schedule with date
headings, a timeline, times and category/creator metadata.

## Ownership

- Kalender 0.31.3 retains date paging, timezone conversion, event queries and
  lane generation. No dependency or SDK pin changes.
- Native `DKalenderCompactMonthBody`, `DCalendarWeekdayHeader`,
  `DKalenderScheduleBody` and `DCalendarScheduleEntry` own reusable presentation.
  Application controls use Select, Button, Dialog and Item from the public kit.
- `EventCalendar` adapts server-expanded occurrences, navigation, event opening
  and domain metadata. The compact toolbar/month is selected below 600 logical
  pixels; Schedule is a monthly agenda available in the view selector.
  iOS and Android open Schedule by default; desktop keeps the site's configured
  default. Explicit routes and subsequent user selections take precedence.
- Schedule scopes Kalender's paginated configuration to the current month,
  giving it a single internal page. This avoids Kalender 0.31.3's shared
  `currentPage` item-map race when animating between populated and empty
  months. Previous/Next/Today navigate schedule months; horizontal swiping
  remains available in the month grid.
- Existing `DCalendar` date selection and embedded topic calendars are unchanged.

## Verification

The focused suite passes 75 tests, including the render fixture. It covers
existing date selection and event views, All/My selection, period navigation,
mobile overflow-day opening, category/creator and continuation metadata, daily
time ordering, RTL multi-week bar geometry, month swipes, 320px/200% schedule
layout and asynchronous requested-date restoration. The loading regression
includes an old payload with an occurrence spanning the newly requested month.
The render fixture also reproduces the populated-to-empty-to-Today crash with
16ms animation frames (the default 100ms widget-test steps skip the race).

The offline fixture in `tool/mobile_events_review_main.dart` uses the production
event page and the new Native styleguide examples. Its render test produces both
views at 320px and 390px in light and Dracula palettes. These are real Flutter
renders, not generated mockups:

```sh
flutter test --no-pub tool/render_mobile_events_test.dart
```

Output is written to `/tmp/mobile-events-review/`. The renderer uses macOS
system fonts and belongs to the local review tools, not the portable test suite.

An isolated, locally signed macOS debug fixture was built with bundle ID
`org.discourse.native.mobile-events-review`. Native review verified event
opening, view selection, All/My selection, crowded-day dialogs and 320px/200%
RTL Schedule in the live app. It identified and corrected clipped timeline dots
from inherited list density. Large-text month review also prompted the shared
narrow weekday labels, subsequently inspected in both the production page and
styleguide at 320px/200%/RTL. Both styleguide callbacks were exercised. The
populated/empty schedule navigation fix passed its final native follow-up:
Month → Schedule → empty October → Today restores September 23 with its
events and no error. No physical iOS/Android device testing is claimed.

Root and full-profile static analysis pass. The macOS debug build and local
signature verification pass. Root and full-profile dependency resolution used
`--enforce-lockfile`; no lockfile, SDK, signing or release settings were changed.

Independent source review completed with no remaining actionable findings.
The reviewer identified the async-loading regression and checked the final
pending-data fix, timeline spacing and accessible weekday fallback, then traced
the upstream schedule-map race and recommended the bounded-month configuration.

Implementation `d14520f63` was integrated with local main `2224baa3f` before
the final 75-test run, root/full analysis, rebuild and native navigation pass.
The newer main's font, button and surface changes are preserved.
