# Notification level menu

`DNotificationLevelMenu<T>` is the shared notification-level trigger and popup,
exported through `package:discourse_native/discourse_ui.dart`. It composes
`DButton`, `DDropdownMenu`, and the dropdown's radio group/items. Options carry
typed values, names, descriptions, bell artwork, and optional subscription
emphasis. The component accepts controlled selection and a nullable callback.

## Application adoption

- Topic header and footer controls use the icon and labeled trigger variants.
- Category controls use the same component with Watching First Post included.
- Chat thread headers and drawer actions use their three supported levels.
  Legacy Muted values display Normal and can be explicitly saved as Normal.

These adapters own server values, optimistic saving, and account-session guards.
Topic/category keys retire menus when the controller, account, site, or target
changes. Chat keys retire menus when the controller, site, or thread changes;
selection also rejects an expired account session before a rebuild.

Both pointer and touch use the Native dropdown. It owns its standard geometry,
selection checkmark, checked semantics, keyboard navigation, focus restoration,
scrolling, and collision handling. The preferred menu width is 336 logical
pixels and shrinks to fit its available viewport. Names and descriptions wrap.
The trigger tooltip and accessible name include the current notification level.

The **Notification level menu** application entry in the UI kit styleguide has
interactive topic, icon-only, category, thread, and disabled examples with local
state. This application composition does not change the frozen upstream
component catalogue or introduce another menu-rendering implementation.

Channel push-notification settings have a separate mute flag and different
values. Their existing dropdown submenu and settings form remain their owners.

## Verification

Flutter 3.47.2 / Dart 3.13.2, on macOS:

- `flutter analyze --no-pub`: no diagnostics.
- `flutter test --no-pub test/d_notification_level_menu_test.dart
  test/category_notifications_test.dart test/notification_menu_ownership_test.dart
  test/chat_thread_workspace_test.dart test/shell_topic_notification_tracking_test.dart`:
  55 passed. Coverage includes controlled and live selection, disabled triggers,
  keyboard selection/dismissal/focus restoration, account replacement,
  navigation, save failure rollback, unread badges, touch selection, and
  narrow RTL layouts with 200% text across light, dark, and Forest palettes.
- The subsequent chat-thread run passed 11 tests, including two additional
  regressions for legacy Muted values and selection after session expiration.
- Notification cases in `topic_reading_integration_test.dart` and
  `chat_shell_integration_test.dart`: 8 passed, including the nested drawer.
- `test/d_button_adoption_test.dart` and
  `test/styleguide/styleguide_page_test.dart`: 22 passed.
- Standalone macOS styleguide and local-data production fixture builds passed.
- After integration with main `759916ca`, all five component/application suites
  above plus `test/topic_inbox_test.dart` passed: **125 tests**. Static analysis
  remained clean. This also covers the newly merged topic-footer sizing and
  compact reader controls. The notification component, adapters, examples,
  Button, Dropdown Menu, and Popover sources match the native fixture build.

Target-platform overrides in widget tests are not iOS or Linux device testing.
