# Message inbox menu

`DMessageInboxMenu<T>` is the personal/group inbox selector, exported through
`package:discourse_native/discourse_ui.dart`. It composes `DButton` and
`DCombobox`, with a search input inside the popup. `DMessageInboxOption<T>`
carries each inbox's value, name, explanation, and icon. Selection is controlled,
and a null callback disables the trigger. The component has no shell or network
dependency; its only owned resource is the search text controller.

The button retains the current inbox name, icon, chevron, tooltip, and accessible
label. Long trigger names truncate while menu names and explanations wrap.
The popup has a preferred width of 336 logical pixels and the Combobox's 288px
height cap, reduced further when the viewport requires it. The result list
scrolls independently beneath the search field.

Opening focuses an empty “Search inboxes…” field. Search matches inbox names
case-insensitively and ignores surrounding whitespace. The first matching result
is highlighted; arrows navigate and Enter selects. No matches displays
“No inboxes found.” without changing the selected inbox. Escape dismisses and
restores button focus. Every reopening clears the previous search. Icons,
descriptions, selected semantics, and the selected checkmark remain available.
The Combobox owns filtering, highlights, keyboard interaction, scrolling,
collision handling, dismissal, and focus restoration.

`MessageInboxTitle` uses the component in the shared Messages header on desktop
and compact layouts. Personal, membership order, restored group labels, folder
navigation, and cached feeds remain intact. Menu identity follows the controller,
site, account session, and forum tab. Callbacks also reject a changed account,
site, tab, or route before rebuilding. Ordinary inbox selection keeps the trigger
mounted for keyboard focus restoration, including Sent falling back to Inbox
when a group is selected.

The **Message inbox menu** application styleguide entry retains five local-state
examples: Personal and groups, Group inbox, Personal only, Many groups, and
Disabled. The search and empty-state instructions now describe the combobox.
The frozen upstream catalogue and shared primitives are unchanged.

## Verification

Flutter 3.47.2 / Dart 3.13.2:

- Component, Messages page, shared Combobox, and Combobox styleguide suites:
  **62 passed**. Coverage includes controlled selection, query reset, partial and
  case-insensitive matching, no matches, whitespace, keyboard focus, disabled
  controls, owner changes, and 320px/200%/RTL examples in light, dark, and Forest.
- Button-adoption and complete styleguide-page suites: **22 passed**.
- Inbox/message cases in full-shell topic reading and group pages: **6 passed**.
- Static analysis and the isolated macOS fixture build passed.
- Logs: `/tmp/inbox-combobox-focused-tests.log`,
  `/tmp/inbox-combobox-styleguide-tests.log`,
  `/tmp/inbox-combobox-shell-tests.log`, and `/tmp/inbox-combobox-analysis.log`.

An initial concurrent Flutter test invocation hit a native-asset signing race
before tests started. Running it after the other build/test process completed
passed. Target-platform overrides are not device testing.

## Native inspection

An isolated, ad-hoc-signed macOS fixture mounted the production `MainContent`
Messages page with in-memory users, groups, and feeds, and opened the real UI kit
styleguide. Strict signature verification, entitlement readback, and launch
succeeded. Production identity/push entitlements were omitted; the real app's
provisioning and account data were unchanged. The review app was quit afterward.

In the dark production header, typing “sup” filtered to support, and Enter
selected it and updated the feed. Space reopened with a fresh query; “xx” showed
the empty state while support remained selected. Escape restored button focus.
At 320px with 200% text and RTL in the light palette, mouse scrolling revealed
the final trust-and-safety row while the search input remained stationary.
The Forest styleguide preview filtered dev groups and selected dev-leads locally.
Native AX exposed an independent text field and descriptive result controls.
CUA clipboard injection timed out; typing was verified with native key events.
No iOS/Linux device or spoken VoiceOver pass is claimed.

The fixture source and signed bundle are retained under
`/var/folders/2m/k_kwhr_j70q64prh4z3r44jc0000gn/T/inbox-combobox-review-osemu5e0`.

The original dropdown composition was merged as
`a1af6f7a6499cfc06ff40895ec46b23d47fe91b8`; this follow-up replaces its popup with
the searchable Combobox while preserving the public inbox component API.

Final integration against main `302fbbaf` passed all 19 inbox component and
Messages page tests again, with clean static analysis. The native-reviewed
component, adapter, examples, Button, Combobox, and Popover are unchanged.
Logs: `/tmp/inbox-combobox-final-tests.log` and
`/tmp/inbox-combobox-final-analysis.log`.
