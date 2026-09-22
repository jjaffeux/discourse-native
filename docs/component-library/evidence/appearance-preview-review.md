# Appearance preview uses production components

Reviewed on 2026-09-22. Implementation: `db2f4dc25`; integration with custom
appearance tabs and backgrounds: `677c0af33`.

The settings preview now composes `ForumIdentityHeader`,
`SidebarDestinationTile`, `TopicFeedMenu`, `TopicListFilterBar`, `TopicListRow`,
`TopicListFooter`, `TopicCreateAction`, and `WorkspacePanel`. Sidebar rows,
topic creation, and footer presentation have one owner shared with the live
app. No Native kit APIs or control styling changed.

Desktop previews lay out a 900 × 560 viewport and then fit it into the settings
column. This keeps the topic pane above its 600px compact-layout threshold.
Touch previews use a 390px viewport without the desktop sidebar. Both retain
the host text scale, platform, font and selected palette. Sample content has
no pointer, focus or accessibility actions and does not load a separate shell.

Verification:

- `dart analyze`: no issues.
- Focused widget tests passed: `forum_theme_preview_test`,
  `forum_theme_editor_test`, `forum_background_noise_test`,
  `appearance_background_test`, `topic_create_button_accessibility_test`,
  `new_topic_drafts_test`, `sidebar_active_destination_test`, and
  `shell_topic_jump_navigation_test`.
- Preview tests cover 320px and 480px columns, 1× and 2× text scale, light and
  dark palettes, macOS and iOS target overrides, input isolation, and live
  theme/font edits. Existing tests cover independent light/dark drafts,
  gradient/noise backgrounds and darker sidebar toggles. The iOS checks were
  widget tests, not device tests.
- Built `tool/appearance_preview_review_main.dart` with
  `flutter build macos --debug --no-pub -t tool/appearance_preview_review_main.dart`.
  Launched an isolated ad-hoc signed bundle through CUA after removing the
  restricted push entitlement from that copy; read back its debug entitlements.
  Inspected light, dark and Dracula palettes, 900px and 340px preview widths,
  and 2× text. The native AX tree exposes the preview as a single image rather
  than actionable forum controls. Also inspected the Sidebar application
  example in the Native styleguide. Rebuilt and launched the integrated source
  after main's theme-tab and background changes.

The native fixture uses offline sample data; no account or network mutations
are needed to inspect it. Full-suite and physical iOS/Android tests were not run.
