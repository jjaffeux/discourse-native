# Event dates in topic lists

Three HTML/CSS alternatives to the unlabelled date beneath a topic title:

- **A — Inline schedule (recommended):** calendar icon, explicit Event label,
  short date and time. The title remains the strongest element.
- **B — Schedule badge:** the same information in a subtle tinted container.
- **C — Calendar stamp:** a month/day tile beside the title, with Event and the
  weekday/time beneath it. Date ranges remain explicit rather than showing only
  their first day.

Open `index.html`, or visit `/event-dates/` on the existing topic-list mockup
server. No build, third-party dependencies, external assets, or network calls
are needed. All names and dates are fixture data, in Europe/Paris in 2026.

Compare all three treatments, focus one, switch Card/Compact, toggle the 390px
pane, and compare light/dark themes. At intermediate comparison widths the
numeric columns are omitted so all three date treatments remain readable;
focusing an option restores its normal list columns. Smaller screens stack
the comparison panels.

Dates open a local schedule dialog with weekday, year, start/end time and
timezone. Topic links and assignment counts open a sample topic dialog.
Escape, outside-click dismissal, focus trapping and restoration use native
HTML dialog behavior. Preview state is reflected in the URL without changing
app preferences.

Examples:

- `?option=all&mode=compact&theme=dark`
- `?option=inline&mode=compact&theme=light`
- `?option=badge&mode=card&width=narrow`
- `?option=stamp&width=narrow`

The fixtures include a regular discussion, the screenshot's Sales Stage Cross
Functional title, user/group assignments, an all-day event and a date range.
Short date labels omit the year only because all samples share the displayed
2026 context. A production implementation must retain the existing event
timezone/all-day conversion and include the year when needed to disambiguate.

Option C was selected and implemented in the Flutter application. Its passive
calendar tile composes Native `DCard` and text; the event line uses a small
`DButton` and opens a Native `DDialog`. No UI kit API changes were needed.
Card, Compact, and Inbox recommendations share a plugin-owned title decoration.
Assignments retain their existing placement. The display-topic-date site setting,
account/event timezone rules, and all-day calendar dates are preserved.

The offline native fixture in `tool/topic_list_modes_review_main.dart` includes
the timed, all-day, multi-day, assigned, and regular topic cases. Native review
covered light/dark Card and Compact, the 390px pane, 200% text and RTL, plus
schedule opening/closing and the full date range. Widget tests also cover 320px,
year boundaries, DST, timezone changes with a schedule open, invalid dates,
site-setting changes, and Escape dismissal. Native Escape could not be confirmed
through the desktop automation; the widget-level route tests pass.

## Review

Reviewed in the Codex browser: dark side-by-side comparison, focused light
layout, light Card mode at a 390px pane, and the calendar stamp at the browser's
smallest tested viewport (355 CSS pixels, 339 pixels excluding scrollbar).
No page or topic overflow was detected. Verified full schedule/date-range
details, Escape dismissal and return of focus to the date trigger. JavaScript
syntax and browser warning/error logs were checked. The preview is left on the
dark Compact comparison.

Implementation validation: targeted static analysis is clean; the macOS debug
fixture builds; 23 focused event/list tests and 139 regression tests pass.
`feed select retains keyboard focus across routes (stacked: true)` still fails
with popular versus topWeekly. The same assertion fails on unmodified main at
714dd521, before merging this change. The installed SDK is Flutter 3.47.4;
the repository's Flutter 3.47.2 pin is unchanged.
