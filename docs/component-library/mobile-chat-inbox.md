# Mobile chat inbox — 2026-09-23

The mobile Chat tab now combines joined public channels and direct messages in
recent-activity order. Recent/Unread and All/Channels/Direct messages filters
compose independently; starred conversations appear once in their chronological
position. Unread state respects muted channels and includes watched threads and
mentions. Message previews preserve the sender so the current user's messages
can display the mockup's `you:` prefix.

The header uses existing Native Select and Button controls. Its compact status
dropdown uses the same `compactToolbar` density as topic notification controls
and reuses the account's custom status, online/offline and notification-pause
actions. Browse channels and My threads remain in the footer. Existing channel
context actions remain available by long press.

Rows compose Item, Avatar, Separator and the existing chat presence avatar.
The kit owns touch targets, control geometry, focus and menu behavior. At narrow
widths with enlarged text the filters and footer actions wrap. No UI kit API or
component implementation was changed.

## Verification

- 165 tests passed in `mobile_shell_test.dart`, `chat_channel_test.dart`,
  `user_status_editor_test.dart` and `user_menu_site_identity_test.dart`. These
  cover mixed ordering, live tracking updates, both filters, own-message
  previews, retained navigation, account actions and 320px layout with enlarged
  text. Mobile widget cases run with both iOS and Android platform variants.
- Seven focused controller/shell integration cases passed for previews, tracking
  state and channel drawer behavior.
- Root `flutter analyze --no-pub`, formatting and `git diff --check` passed.
- The optional plugin dependency boundary suite reports three pre-existing
  failures in the untouched Onebox styleguide imports/ownership and the events
  plugin's internal typography import. This change introduces no new boundary
  exception.

`tool/mobile_chat_review_main.dart` is an offline fixture mounting the production
mobile panel and account actions. Built with
`flutter build macos --debug --no-pub -t tool/mobile_chat_review_main.dart`, it
was launched as an isolated, locally signed macOS app and inspected through
native UI automation. The review exercised filters, unread results and presence
actions at 390px and 320px, Dracula and Light palettes, and normal/150% text.
The fixture uses iOS control density; this native pass is not a physical iOS or
Android device run. Widget tests additionally exercise saving status and pausing
and resuming notifications without writing to a real account.
