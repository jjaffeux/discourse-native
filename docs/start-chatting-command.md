# Start chatting command palette

The desktop Cmd+K / Ctrl+K flow uses a 520px Native command palette based on
[the approved HTML mockup](start-chatting-mockup/index.html). Existing sidebar
and drawer actions open the same dialog.

The imperative `showDDialog` + `DDialogContent` composition uses the same dialog
owner as `DCommandDialog`. `DCommand` owns search editing, active rows, keyboard
navigation and scrolling. The app adapter retains the remote search debounce,
request generations, API writes and navigation. No UI-kit changes are needed.

- Existing conversations appear in descending last-message activity order,
  with stable ordering for ties, participant avatars and relative timestamps.
- Search results use labeled type groups in their original relevance order;
  local Command filtering is disabled so server matches and ranking survive.
- Arrow keys and Return navigate/open/add. Escape and the platform's primary+K
  shortcut close the dialog. IME key ownership stays with Command and the input.
- Group creation supports a name, removable members, server-configured limits,
  disabled results and pending/error feedback. Empty group search invites typing;
  the mockup's illustrative suggested people are not fabricated in the app.
- Search generations protect query changes, group transitions and writes. A
  dismissed dialog cannot navigate on a late create/upsert completion.
- Native controls retain touch targets and text scaling. Keyboard hints yield
  space to actions on narrow or scaled layouts. Mobile shares the Native controls.

The HTML prototype remains design evidence only. Colors, radii, input/button
heights, keycaps and avatar fallbacks use the current Native presets in the app.

## Verification

- Root `flutter analyze --no-pub`: no issues.
- 223 affected tests passed on the candidate integrated with current main,
  across the eight dialog tests, chat navigation, channel-list widgets, shell
  integration, Command, Button adoption and control style adoption.
- Widget coverage includes macOS keyboard routing and focus restoration,
  disabled recipient skipping, server relevance, stale requests, group limits,
  recipient removal, error recovery, and narrow RTL at 200% text scale.
- Built `tool/start_chatting_review_main.dart` as a macOS debug app and inspected
  an isolated ad-hoc-signed copy with debug entitlements and no push/team identity.
  The fixture uses fake transport and no real account writes.
- Native macOS CUA: light/dark recent conversations, typed group/user searches,
  Return selection, group naming, member removal, group creation, arrow/Return
  opening and Escape dismissal. The injected native Cmd+K chord produced no
  visible change; its open/close routing is verified by widget tests. No iOS,
  Windows or Linux device testing, or spoken screen-reader pass, is claimed.

Run the offline native fixture with:

```sh
flutter run -d macos -t tool/start_chatting_review_main.dart --no-pub
```
