# Message inbox menu

`DMessageInboxMenu<T>` is the personal/group inbox selector, exported through
`package:discourse_native/discourse_ui.dart`. It composes `DButton` and
`DDropdownMenu` with radio items. `DMessageInboxOption<T>` carries each inbox's
value, name, explanation, and icon. Selection is controlled, and a null callback
disables the trigger. The generic component has no shell or network dependency.

The button shows the current name and icon with a chevron. Long names truncate
in the trigger; the tooltip and accessible name retain the full value. Menu
names and explanations wrap. The preferred width is 336 logical pixels, reduced
to fit the available viewport. Dropdown Menu owns scrolling, collision handling,
the selected checkmark and radio semantics, keyboard navigation, dismissal, and
focus restoration. Touch uses the same dropdown with the kit's touch sizing.

`MessageInboxTitle` adopts the component in the shared Messages header on desktop
and compact layouts. Personal, membership order, restored group labels, and
folder navigation remain intact. The shell still validates group membership and
keeps each inbox/folder's cached feed. Menu identity follows the controller,
site, account session, and forum tab. Callbacks also reject a changed account,
site, tab, or route before the next frame. Ordinary inbox selection keeps the
trigger mounted so keyboard focus returns correctly, including Sent falling
back to Inbox when a group is selected.

The UI kit styleguide's **Message inbox menu** application entry has five local
state examples: Personal and groups, Group inbox, Personal only, Many groups,
and Disabled. The many-groups example includes long names and a scrolling list.
The frozen upstream catalogue is unchanged. Other `ChoiceMenuAnchor` consumers
are outside this migration.

## Verification

Flutter 3.47.2 / Dart 3.13.2:

- `flutter test --no-pub test/d_message_inbox_menu_test.dart
  test/message_inbox_page_test.dart test/d_button_adoption_test.dart
  test/styleguide/styleguide_page_test.dart`: all **40 tests passed** after
  integration with main `7fb2dd29`.
- Inbox/message cases in `topic_reading_integration_test.dart` and
  `group_pages_host_test.dart`: all **6 tests passed**, including full-shell
  group selection, restored navigation, and loading state.
- Component coverage includes controlled and live selection, checked semantics,
  disabled controls, keyboard dismissal/focus, and all five examples in light,
  dark, and Forest palettes at 320px, 200% text, and RTL. End reveals the final
  option even with scrolling and collision constraints.
- Messages coverage includes folder/feed caching, Personal without groups,
  restored group labels, stale account/site/route actions, removal on navigation,
  keyboard inbox switching, and compose permissions. Layout tests use macOS,
  iOS, and Linux target-platform overrides; these are not device tests.
- Static analysis and the isolated macOS fixture build passed.

## Native inspection

An isolated macOS fixture mounted the production `MainContent` Messages page
with local users, groups, and feeds, and opened the real UI kit styleguide.
The ad-hoc bundle retained sandbox/debug networking and JIT entitlements,
omitted production identity/push entitlements, passed strict signature
verification, and launched successfully. The review app was quit afterward.

CUA inspection verified the dark 640px header and dropdown, switching to
dev-managers, updated feed content and group icon, radio semantics, Space
reopening after selection, and Escape dismissal. Light and Forest previews
used a bounded 320px nested Navigator, 200% text, and RTL. Text wrapped within
the viewport, the trigger truncated without overflow, and End revealed the
final trust-and-safety row and its complete description. Enter selected that
inbox and updated the production page.

The styleguide's new page displayed all five examples. The first example
selected engineers-emea locally; the Many groups example showed a truncated
long trigger and scrolled to the final option with End. The generic Dropdown
Menu retains the accepted compact Native row, border, radius, and checkmark
styling, matching the previous notification-menu migration.

Fixture source and signed bundle are retained under
`/var/folders/2m/k_kwhr_j70q64prh4z3r44jc0000gn/T/message-inbox-review-vf3w_n3p`.
No iOS/Linux device or spoken VoiceOver pass is claimed.

The native-reviewed inbox component, adapter, examples, Dropdown Menu, and
Popover are unchanged after integration. Main's already accepted DButton change
only adds the forbidden cursor for disabled buttons. Final logs are
`/tmp/message-inbox-integration-tests.log`,
`/tmp/message-inbox-shell-tests.log`, and
`/tmp/message-inbox-integration-analysis.log`.

Merged from the repository's main checkout into local main as
`a1af6f7a6499cfc06ff40895ec46b23d47fe91b8`. No remote push was performed.
