# Topic creation split button

The New topic action now composes `DButtonGroup`, `DButtonGroupSeparator`,
`DDropdownMenu`, and `DDropdownMenuItem` through the public Native entrypoint.
The group owns joined corners and RTL geometry. The dropdown owns popup
placement, dismissal, menu navigation, and trigger focus. Recent draft icons,
titles, the four-item limit, resume behavior, and the all-drafts destination
remain application-owned.

The migration exposed an autofocus gap in asynchronous menus. Menu autofocus
now waits for the first enabled item to register, applies once, and respects
`autofocus: false` and an existing item focus. Loading completion after dismissal
cannot reopen the menu or move focus.

## Verification

Flutter 3.47.2 / Dart 3.13.2, macOS, 2026-09-10:

- Static analysis of the changed application, component, and test files passed.
- Focused dropdown, context menu, menubar, button group, and their dropdown/button
  group styleguide tests passed, including delayed registration, enabling,
  autofocus opt-out, and retention of the user's focused item.
- Topic creation and recent-draft integration tests passed, including loading,
  empty/error responses, dismissal during loading, keyboard navigation and
  restoration, separate callbacks, scaled text, RTL corners, icons, the four-row
  limit, draft resumption, and navigation to all drafts.
- An initial run exposed two stale sidebar assertions, also reproduced with
  both production files restored to baseline `a75a0e8e`. Current main fixed
  those assertions independently. After integration with `fa01bb4b`, all
  **107** focused component/application tests and all **27** draft-list tests
  passed, including the newly merged draft editing behavior.

## Native inspection

An isolated, locally signed macOS debug fixture mounted the production
`TopicCreateButton` in labeled, compact labeled, and compact icon modes alongside
the Button Group styleguide's **Dropdown menu** example. Its fake API delayed
drafts by 800 ms and returned six drafts. The isolated bundle retained debug
capabilities and omitted production identity and push entitlements; strict
signature verification and actual launch succeeded.

CUA inspection confirmed joined surfaces and the menu in dark mode at a 680px
toolbar width, and light mode at a 320px toolbar width with 200% text. These
were layout widths inside a desktop window. Keyboard Down moved focus after
loading; Escape followed by Space closed and reopened the menu; the New topic
action incremented its independent callback counter. The visible styleguide
composition used the same Native components.

Later CUA coordinate actions returned `noWindowsAvailable`, limiting further
native interactions. RTL, empty/error states, and composer resumption were
verified by widget/integration tests. No iOS/Linux device or spoken VoiceOver
pass is claimed. The temporary app was quit and the desktop lease released.

The fixture source, build/test logs, and isolated bundle are retained locally
under `/tmp/new-topic-dropdown-review-03a909sy`.
