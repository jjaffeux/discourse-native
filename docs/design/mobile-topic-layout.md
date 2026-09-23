# Mobile topic layout

The September 23, 2026 mobile reference moves topic-wide actions out of the
reader footer. Mobile navigation now owns the topic Reply action, restoring
New topic after returning to the list. Reply remains visible as the tab buttons
scroll and respects the topic's reply permission.

The reader overlays its existing progress popover at the bottom right, using
Native Button's pill shape. Its width stays within the reader, and end padding
keeps the last post's actions clear of the overlay. Bookmark, notification,
plugin property, private-message archive, and wrench actions live with the
header taxonomy and wrap on narrow screens. Editable tags open their existing
picker directly; the separate pencil remains a desktop affordance. All controls
reuse the public Native library.

The follow-up reference uses shorter header actions than its taxonomy chips.
With the user's approval, Native Button now provides
`DButtonDensity.compactToolbar`: 24px-high surfaces, 32px-wide icon-only actions,
14px icons and at least 48px touch targets, with text-scaling growth. Mobile
bookmark, notification, assignment and wrench actions use the preset; the
notification trigger also shows its dropdown chevron. The Button styleguide's
Compact toolbar example includes interactive, disabled and loading states.

## Verification

- `flutter analyze --no-pub`: no issues.
- Compact action follow-up: `flutter test --no-pub test/d_button_test.dart test/d_button_group_test.dart test/d_notification_level_menu_test.dart test/mobile_topic_layout_test.dart test/assign_plugin_test.dart`: 146 passing tests, including painted dimensions, outer-edge touch activation, keyboard activation, semantics bounds, text scaling, disabled and loading states on macOS/iOS/Android widget platform overrides.
- Compact action native review: rebuilt and launched the isolated macOS mobile
  fixture, inspected the Dracula header at a narrow window, and exercised the
  bookmark sheet, notification selection and wrench menu. Rebuilt and launched
  the standalone Button styleguide; reviewed Compact toolbar and Control
  consistency in light and dark palettes, and activated bookmark and assignment
  examples. Both bundles used local ad-hoc debug entitlements without push or
  team identity; the real application's provisioning stayed unchanged.
- `flutter test --no-pub test/mobile_topic_layout_test.dart test/mobile_shell_test.dart test/topic_progress_test.dart test/topic_progress_lifecycle_test.dart`: 86 passing tests.
- Layout coverage includes 320, 390, 496, and 800 logical pixel widths and
  200% text scaling, with iOS and Android widget platform overrides. Interaction
  coverage exercises tag editing, bookmark and notification menus, wrench
  actions, post navigation, Reply, return to the list, and reply permissions.
- `flutter test --no-pub tool/render_mobile_topic_test.dart`: production-widget
  renders at 496/390/320 widths in Dracula and neutral light themes, using the
  Flutter test renderer and local SFNS fonts. These are visual review fixtures,
  not device screenshots.
- `flutter build macos --debug --no-pub -t tool/mobile_topic_review_main.dart`:
  successful. Ran an isolated, locally signed macOS fixture with the iOS theme
  override. Inspected wide and narrow windows; exercised progress to post 4,
  Reply and composer dismissal, tag editing, bookmark, notification, and wrench
  menus. This checks the native host with mobile layout, not an iOS/Android device.

The broader topic/inventory run has six failures reproduced unchanged at the
starting commit `c3d48d694`: five stale geometry assertions in
`topic_inbox_test.dart` (title/lock spacing, desktop footer sizing/spacing, and
post-reply spacing) and the missing existing composer styling exception in
`control_style_adoption_test.dart`. The new mobile pill exceptions are recorded
in that inventory without changing the unrelated composer exception.
