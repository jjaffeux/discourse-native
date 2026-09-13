# Remaining command-menu migrations

The three remaining production consumers of the old `CommandMenuAnchor` now
compose `DDropdownMenu`, `DDropdownMenuContent`, and `DDropdownMenuItem` through
the public Native entrypoint:

- Group header actions retain the admin-only Delete group action and its exact
  group-name confirmation.
- Member management retains owner, primary-group, and removal actions, with a
  Native separator before removal. Open menus follow current permissions,
  ownership labels, and busy state. Removing or replacing the owning row closes
  the menu; pending removal confirmations still reject retired rows.
- Chat's Add to message menu retains Upload images and Insert GIF, feature and
  busy-state gating, and picker focus handling. The menu closes when the
  composer/channel or editing target changes. Retained callbacks cannot open
  a picker for a replacement composer.

Each trigger passes through the kit's focus node, popup semantics, expanded
state, and activation. Explicit semantics boundaries keep independent popups
reachable from the native accessibility tree. The kit owns row appearance,
keyboard navigation, collision handling, scrolling, and dismissal.

`command_menu.dart` and its obsolete production-adapter review card are removed.
A repository-wide Dart search found no remaining references to
`CommandMenuAnchor`, `CommandMenuOption`, or `showCommandMenu`.

## Verification — 2026-09-13

Flutter 3.47.2 / Dart 3.13.2:

- Root `dart analyze`, formatting, and `git diff --check` passed.
- 127 selected tests passed across `group_page_test.dart`,
  `group_pages_host_test.dart`, `group_member_menu_ownership_test.dart`, and
  `chat_composer_test.dart`. These cover menu activation/dismissal, focus,
  current ownership/busy state, row and channel replacement, confirmations,
  and image/GIF handling in drawer and full-page composers.
- The full run found four unrelated chat selection-formatting tests overflowing
  the toolbar in `composer_panel.dart` by 8px. All four also fail on unchanged
  baseline `8c388842`; the focused passing run excludes only those names using
  `--name '^(?!.*(?:Command-E wraps|Command-B and Command-I|Command-L links|shares the selection formatting)).*$'`.
  A fifth baseline failure used a stale Material menu-item finder for Edit;
  its two assertions now target the existing Native dropdown and pass.
- An isolated macOS debug build passed strict signature verification and
  launched successfully. CUA inspected all three production menus in dark mode
  at 1120px pane width and light mode at 390px/200% text. Menu text wrapped
  without clipping. Keyboard selection changed the fake member's primary group
  and invoked the fake image picker, restoring composer focus. Escape dismissed
  menus. No other-device or spoken VoiceOver verification is claimed.

The temporary fixture source is retained at
`/tmp/remaining-dropdown-evidence/remaining_dropdown_review_main.dart`; logs
use `/tmp/remaining-dropdown-*.log`. The shared dropdown implementation is
unchanged from the reference/styleguide review recorded in
`topic-actions-dropdown.md`.
