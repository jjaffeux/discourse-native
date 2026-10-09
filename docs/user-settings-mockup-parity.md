# User cards, status, preferences, and directory parity

Source: `discourse-native-mockups` at `c39ad5079e36ccd40a2604c43b513195d5c125a2`, following the previously shipped `54ba01c` baseline. This group covers `b1e5fbf`, `897dca0`, own-user card behavior from `7308ec3`, directory/participant/count behavior from `04b4125`, and the fixture audit in `9eb8d4e`.

## Implemented behavior

- Profile cards and the status editor share `UserCardHeader`: the real forum name, username, title, avatar, role, suspension, and optional card banner. `card_background_upload_url` resolves relative HTTP(S) URLs from the forum response. Missing banner data adds no invented artwork.
- The approved Native `DBubbleVariant.status` paints one continuous outline around a pill and downward caret, mirrors in RTL, and shows descendant input focus. The editor composes it with the existing Native emoji action and borderless input. Its server save/clear, emoji catalogue, custom expiry, account timezone, and notification pause behavior remain active.
- Desktop and touch profile menus open the current user's real card after dismissing their source menu. Own cards expose Preferences. Existing post authors, mentions, directory identities, and participant avatars use `UserCardTarget`; its actions now use Native `DButton` with visible bounds. Directory avatars, usernames, and real names are separate targets, so whitespace does not activate them.
- Preferences and forum Settings share Native section tabs. Preferences show one section, arrange labels/help beside Native controls where space permits, and save changes immediately. Pending changes drain in order, including a choice reversed during an in-flight write. Failed saves retain the draft and offer Retry. Account leases, capability gates, plugin sections, and confirmed account mirrors remain enforced.
- Header tuning remains available in the Interface section, per the explicit coordination direction to preserve that existing product capability.

## Source boundaries

The production directory already consumes server columns, counts, groups, filters, sorting, pagination, and real user data. Topic faces already follow the server's ordered poster data; this change adds card actions to those faces. The final mockup's seeded people, counts, banners, discussions, logos, and other sample content were not copied into application data. The generated image and identity in the rendering test are test-only fixtures. Global person-search navigation is owned by the separate search group.

## Validation

- Focused run: 297 passing tests across 22 directly related files. The ten failures in `plugin_user_menu_widget_test.dart` (seven) and `user_menu_activation_ownership_test.dart` (three macOS replacement-menu cases) also fail on unchanged main at `9ab73cc37`, with the same assertions and overlay failure paths.
- Earlier `user_menu_site_identity_test.dart` comparison at unchanged `84262ec96`: three existing failures (invite menu replacement, old minimum-target assertion, and site replacement overlay teardown). The status-editor label assertion was updated to the real input semantics and verified independently.
- Targeted `dart analyze` on every changed Dart file: no issues. `git diff --check`: clean.
- The preserved preference checks cover plugin/capability gates, loading and save semantics, known-timezone filtering, account-generation reload, confirmed timezone/like/bookmark/chat mirrors, failure retry, and stale-account callbacks. New checks cover immediate writes and in-flight reversal.
- `user_card_status_parity_test.dart` renders the shared header/editor in light and dark themes, the editor at 320px/200%/RTL, tabbed preferences, and the real directory-name action. It also exercises own-card navigation through desktop dropdown and mobile sheet. The rendered PNGs were inspected; the 200% mobile footer stacks its actions to retain their labels.

Reproduce the rendered fixtures:

```sh
USER_PARITY_EXPORT_DIR=/private/tmp/users-parity-render flutter test test/user_card_status_parity_test.dart
```

These are deterministic Flutter widget renders and account/API fixture tests; they are not evidence of a live-forum write or a physical-device run. No full test suite was run.

Integration check: rebased onto main `9ab73cc37`; targeted analysis remained clean and 108 focused tests passed across the shared card/editor, preferences/settings, topic metadata, and Native bubble surfaces.
