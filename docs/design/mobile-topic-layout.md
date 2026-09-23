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
reuse the public Native library; no UI kit APIs changed.

## Verification

- `flutter analyze --no-pub`: no issues.
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
