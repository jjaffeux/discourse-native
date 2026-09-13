# Application control adoption

The remaining Material action buttons, icon buttons, menus, segmented controls,
and dropdown fields now use the Native UI kit through `discourse_ui.dart`.
Application code uses the kit's variants, size presets, focus and loading behavior,
and accessible touch targets. `AGENTS.md` makes this mandatory for all application
UI, including plugin screens and styleguide examples. The adoption test no longer
allows application exceptions for raw framework buttons, menus, or selectors.

## Verification on 2026-09-13

- 835 focused tests passed across the affected application surfaces, keyboard
  navigation, accessibility, and adoption guards.
- Root `flutter analyze --no-pub` passed without diagnostics.
- The isolated macOS debug build passed without changing signing, provisioning,
  release settings, or the Flutter SDK.
- Native inspection covered menu activation and recurring attendance callbacks,
  tab search and selection, tab context actions, light/dark rendering, and 200%
  text. The tab context menu was widened after inspecting its large-text layout.
- Existing lightbox tests now schedule the image callback's frame explicitly;
  they no longer depend on a Material button animation to trigger it.

## Popup accessibility boundaries

Migrated popup roots have explicit semantics boundaries. Without these,
independent overlay anchors inside a card could merge, leaving menu entries
unreachable from the native accessibility root. Widget finders alone still
found those entries, so the original tests did not expose the failure.

`test/event_card_semantics_test.dart` replays the traversal tree actually sent to
Flutter's native accessibility bridge. The version without boundaries produces
orphaned event-menu nodes; the corrected version passes. Native inspection of the
corrected build also exposed all menu items, accepted keyboard selection, and
completed the tab/attendance sequence without accessibility-tree errors.

The inspected fix is `28e8fd52`; changes after its native build were comments and
test cleanup only. No UI kit component implementation was changed.

## Remaining native verification limitation

Switching the isolated fixture from Actions to Calendar still crashes when macOS
reads the new accessibility tree, including when no popup has been opened. A
comparison fixture restored the exact pre-migration EventCard, EventCalendar,
ForumTabsBar, and VoiceToolbarControl sources from
`bb01472d7793a03cd3d8e701d7c80ee080f30e93` (only import/export paths were relocated).
That fixture reproduced the same failure on the same transition.

Both reports show `EXC_BAD_ACCESS` at `0x48` in
`flutter::FlutterPlatformNodeDelegate::ChildAtIndex(int)`, called through
`AXPlatformNodeCocoa AXChildrenInternal`. The original local reports are in
`~/Library/Logs/DiagnosticReports`:

- Migrated: `Discourse-2026-09-13-224635.ips`, SHA-256
  `f9a5c6d8f35290a83ab4204fbcb46fcf56a1e9f4f22d6b57892a8f8d5fa6030e`.
- Pre-migration: `Discourse-2026-09-13-225109.ips`, SHA-256
  `ffa1ad80cf1c8fb1d13b9801c881248c742666ef86b2b4abffb37eef40434808`.

This comparison establishes that the migration is not required to trigger this
calendar-fixture failure. Its framework cause remains unresolved; native calendar
and timezone checks were not completed. Their automated application tests passed.
No spoken VoiceOver or physical mobile-device pass is claimed.
