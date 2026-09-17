# Forum settings review — 2026-09-17

Appearance now lives in **Settings**, opened from the forum identity menu.
The dialog composes the existing Native Dialog, Field, Select, and Button
components without changing their APIs or styling.

Each canonical forum URL retains its own System, Light, or Dark choice. Existing
forums inherit the former app-wide choice on first migration; new forums start
with System. Aggregate and app-wide Settings follow system appearance.

## Verification

- `flutter analyze --no-pub`: passed.
- Focused tests: `forum_settings_test.dart`, `forum_settings_dialog_test.dart`,
  `site_theme_app_test.dart`, `app_settings_page_test.dart`,
  `app_settings_navigation_test.dart`, `app_settings_controller_test.dart`,
  `app_settings_store_test.dart`, `add_instance_lifecycle_test.dart`, and
  `instance_reordering_test.dart`: passed, with the two narrow dialog tests rerun
  after correcting their scrolling and semantics-handle cleanup.
- The existing `shell_navigation_integration_test.dart` test named
  `the forum menu opens actions below the header`: passed.
- `flutter build macos --debug --no-pub --target=tool/forum_settings_review_main.dart`:
  passed. The fixture uses in-memory data and preferences.
- Native macOS inspection: logo menu, dark dialog, immediate switch to Light,
  Escape dismissal, switching between two forums and restoring Light, compact
  navigation menu and its forum settings dialog, and the app-wide Settings form.
  Native accessibility exposed separate Appearance and Close controls.
- Widget layout checks covered 360×640, 200% text, RTL, both brightnesses,
  scrolling to the selector, selection, and Escape dismissal. These were widget
  checks, not mobile-device testing.

The isolated review bundle used `org.discourse.native.review.forumsettings` and
the existing local debug entitlements, without push or team identity claims.
Validation used the installed Flutter 3.47.4 / Dart 3.13.3; the repository's
Flutter pin and lockfiles were unchanged. No UI kit components were modified.
