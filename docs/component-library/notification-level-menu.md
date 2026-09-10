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

Native inspection at 200% text exposed a shared Dropdown Menu overflow bug:
Popover measures against the viewport, then lays out again against the space
beside its trigger. The menu's deferred measurement now uses the final
constraints. Menus that fit the whole screen but exceed their available side
gain a scroll viewport, and wheel input or End can reveal the final option.

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
- The overflow correction passed 89 focused Dropdown Menu, notification-menu,
  Popover, Context Menu, Menubar, and dropdown styleguide tests, including a new
  regression for collision-only overflow and scaled notification menus anchored
  midway down a narrow viewport. All 53 notification adapter/tracking tests
  passed again, and static analysis remained clean.
- The collision-overflow regression uses desktop row metrics and fails against
  the original Dropdown Menu: no scroll viewport is created. With the correction,
  wheel scrolling and revealing the final option with End both pass.

Target-platform overrides in widget tests are not iOS or Linux device testing.

## Native inspection

An isolated, ad-hoc-signed macOS fixture mounted the production topic header,
topic footer, and category header controls with an in-memory shell/API. It also
opened the real UI kit styleguide. The bundle retained sandbox/debug networking
and JIT entitlements, omitted production identity/push entitlements, passed
strict signature verification, and launched successfully.

CUA inspection confirmed the dark topic dropdown, its radio semantics, keyboard
selection, trigger updates, Space reopening after selection, and Escape
dismissal. Light and Forest previews used a 320px content column, 200% text,
and RTL. After the overflow correction, End visibly scrolled the category menu
to Muted, fully revealing its explanation and the scrollbar; Enter updated the
production category trigger. The Forest topic menu retained readable wrapping
and selection indicators. These are layout widths within a desktop window.

The real styleguide's Notification level menu page displayed all five examples.
Its topic example saved Watching locally and updated the trigger; the thread
example rendered Normal, Tracking, and Watching with the selected checkmark.
The Mac locked before the final thread-example selection and app cleanup, so
UI interaction stopped and the desktop lease was released. The review app may
remain open. No iOS/Linux device or spoken VoiceOver pass is claimed.

The fixture source and final signed bundle remain under
`/var/folders/2m/k_kwhr_j70q64prh4z3r44jc0000gn/T/notification-level-review-o318l9ou`.
The final component/app and shared-menu test logs are
`/tmp/notification-level-app-final-tests.log` and
`/tmp/notification-level-overflow-tests.log`; the final desktop-specific
dropdown suite is `/tmp/notification-level-dropdown-final.log` (31 passed).
