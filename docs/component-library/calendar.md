# Calendar

Calendar is the inline, date-only selection primitive. It is backed by the
repository's pinned `kalender: 0.31.3`; `DKalenderTheme` also gives existing
Kalender event views the same live Discourse tokens without replacing their
event layout, recurrence, timezone, or navigation ownership.

## Frozen source

- Source: shadcn Base UI / base-nova Calendar documentation, frozen 2026-09-09.
- Frozen Markdown SHA256: `9268f3aa428b4eb36bfbd957644f9d681beab0d49575f779a2cd2620f81a58b4`.
- Independently fetched base-nova registry SHA256: `cc9ff16599d1664cec2d6a91ba82d0927953d8eedd51a7d56bba48a6522c28eb`.
- Upstream behavior reference: [React DayPicker](https://react-day-picker.js.org).
- Frozen sections reproduced: Basic, Range Calendar, Month and Year Selector,
  Presets, Date and Time Picker, Booked Dates, Custom Cell Size, Week Numbers,
  RTL, timezone guidance, and Persian / Hijri / Jalali engine substitution.

The Flutter mapping keeps the source's 8px outer padding, 16px multi-month gap,
28px default day geometry, 38px fixed-week preset geometry, 40/48px custom-cell
example, 14px day text, approximately 13px weekday/week text, medium radius,
primary selected endpoints, muted today/range fill, disabled opacity, booked
strike-through, and a 3px exterior focus ring. Touch platforms retain a 48px
actionable target while the desktop artwork stays compact.

## Public API and ownership

`DCalendar` supports typed single, multiple, and range values through
`DCalendarSingleSelection`, `DCalendarMultipleSelection`, and
`DCalendarRangeSelection`. A non-null `selection` or `displayedMonth` is
controlled; initial values and `DCalendarController` cover local/imperative
ownership. The controller can select, clear, reveal a month, and focus a day.
Borrowed controllers and focus nodes are never disposed.

`DCalendarDate` represents a civil date with no timezone or time of day. Use
`DCalendarDate.fromInstant(instant, location)` to derive a day and
`date.atTime(location, ...)` to create a zoned instant. This explicit boundary
prevents UTC-midnight offset bugs. Gregorian month arithmetic clamps leap-day
and month-end values.

Supported behavior includes:

- controlled and initial selection/month values;
- disabled, hidden, booked, outside, bounded, minimum/maximum range, and
  exclude-disabled range rules;
- configurable first weekday, fixed six-week pages, week numbers, multiple
  months, custom cells, and localized formatter callbacks;
- arrow-day/week navigation, Home/End week edges, Page Up/Down months,
  Shift+Page Up/Down years, Enter/Space selection, focus reveal, pointer and
  touch input, semantics, and logical RTL range geometry;
- live color, radius, type, reduced-motion, brightness, and locale updates.

`DCalendarDayButton` is the shared public day-header presentation used by the
real event calendars. `DKalenderTheme` is the shared Kalender adapter for month,
week, day, schedule, timeline, overlay, and event surfaces. Later Date Picker
owns input parsing and popover lifecycle; Calendar deliberately does not.

`DKalenderCompactMonthBody` presents read-only event summaries inside a Kalender
month view. It uses Kalender's controller, page calculator and public layout
frames, accepts an event-color callback and layout strategy, and opens a day
through `onDayPressed`. Weeks grow to fit up to four thin event lanes and a
per-day `+N` count. Whole-day Native buttons carry full dates and event counts;
bars are decorative. Outside-month cells are blank, and continuing bars are
clipped at month/week boundaries with directional end caps.

`DCalendarWeekdayHeader` switches from localized short to narrow weekday names
when text scale and column width require it, retaining full spoken labels.
`DCalendarScheduleEntry` renders an optional date heading/Today badge, a date
rail, time, colored marker, title and metadata through an actionable Native
item. At large text sizes, time stacks above the details. `DKalenderScheduleBody`
removes Kalender's default list-row spacing around these custom entries; pair
it with zero-width leading dates and empty month-header builders.

## Calendar systems

Kalender 0.31.3 pages are Gregorian `DateTime` pages. Locale-specific Gregorian
labels, custom numerals, first weekday, and RTL are functional. The official
React example implements Persian/Hijri/Jalali by replacing its underlying
calendar engine. Kalender does not expose an equivalent non-Gregorian engine in
the pinned version, so this port does not falsely relabel Gregorian math as a
different chronology. A correct alternate system requires a future Kalender
engine/calendar-math seam; `DCalendarDate` remains the stable caller boundary.

## Production adoption

`EventCalendar` uses the compact month body below 600 logical pixels, with
Native All/My and view selectors plus a second navigation row. Schedule uses
a Kalender agenda bounded to one month and the Native timeline entries. Event
metadata includes category, creator and civil-day continuation counts. Routes,
Today and async month loading restore the selected date; populated-month
refreshes retain the current scroll position. The web link maps Schedule to
FullCalendar's `listMonth` view. Day details use Native Dialog and Item.

The desktop month, week, day and yearly agenda keep their existing Kalender
layouts. Server-expanded recurrence, occurrence opening, all-day boundaries
and reader timezone conversion remain in the event adapter. See
[the mobile implementation and verification record](mobile-event-calendar.md).

`TopicCalendar` remains a domain-specific Kalender composition for embedded
post geometry and split multi-week event bars. It now scopes
`DKalenderTheme(compactMonthLayout: false)` around that existing layout, so its
paint and typography share the Calendar tokens while its lanes, bar widths,
reply dates, paging and navigation remain unchanged. Its full focused suite,
including the two-segment 1.5:1 width geometry assertion, passes after adoption.

## Dependency preparation

- Select was prepared from `423d81eeaf9bdda9412fa2068d4f8132fbfb53de`
  plus `69e5ec663e92bb61fa734ee43b6c3e738e96961e`; its accepted-main merge is
  `57bbeb94368649a4665483180e4f5c84b5f33856` with tracking follow-up
  `94a65e00c525d6096f12be94fcc2ec9bbaf888ff`.
- Field was reconciled from accepted-main merge
  `5cd7f3694498e4e09e3c114639baca834b56705e`.
- Input Group was prepared from reviewed source `6775be52` after reconciliation
  with the accepted Input API. Calendar's final candidate replaces that
  provisional tree with accepted-main merge `d1de717b1e2d1eeaf06d86dafe1452662d05e368`
  and tracking follow-up `eeb9a9cabc8713d12c2e9c579be7e22934a60b34`;
  the Date and Time composition uses that accepted public API.

The independent Calendar reviewer owns final browser/native comparison,
dependency reconciliation on current `main`, evidence, status, and merge.
