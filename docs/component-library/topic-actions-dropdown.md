# Topic actions dropdown

The topic header's wrench action uses `DDropdownMenu`,
`DDropdownMenuContent`, and `DDropdownMenuItem` through the Native public
entrypoint. Its icon-only `DButton` passes through the menu's focus node,
popup semantics, expanded state, and activation. The popup aligns to the
trailing edge of the trigger and uses a 224px width; the kit owns row sizing,
icons, destructive styling, collision handling, scrolling, and dismissal.

Each opening captures the displayed commands, topic, action intent, and account
lease together. Header rebuilds preserve that snapshot until dismissal. Every
selection still checks current permissions, busy state, controller identity,
and account ownership. The next opening reads the latest topic state.

## Verification — 2026-09-13

- Flutter 3.47.2 / Dart 3.13.2: root `dart analyze` passed.
- `flutter test --no-pub test/topic_actions_menu_test.dart
  test/topic_actions_integration_test.dart`: all 82 tests passed, including
  live refresh/navigation/account replacement guards, keyboard activation,
  arrow navigation, typeahead, Escape, outside dismissal, and focus restoration.
- The isolated macOS debug build and strict signature verification passed.
  CUA inspected the real `MainContent` topic header with all six screenshot
  actions in dark mode at 1120px pane width and in light mode at 390px/200%
  text. Labels remained readable, including the wrapped visibility action.
  Pointer opening, Down navigation, and Escape dismissal were exercised.
- Inspected the Native styleguide's Destructive dropdown example and the
  official Base UI dropdown page's Destructive example. The shared component
  implementation is unchanged. No pixel-equality, other-device, or spoken
  VoiceOver verification is claimed.

The temporary fixture derives from `tool/topic_header_handoff_review_main.dart`
with fake moderation permissions and a topic flag catalogue. Source is retained
at `/tmp/topic-actions-dropdown-evidence/topic_actions_dropdown_review_main.dart`;
build, analysis, and test logs use `/tmp/topic-actions-dropdown-*.log`.
