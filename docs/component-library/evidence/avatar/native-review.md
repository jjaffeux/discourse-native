# Avatar verification record

Implementation checkpoint: `4c7783272937f3db8fb523389f97c75ac4bdefd7`.
Flutter 3.47.2, Dart 3.13.2. All test commands use the recorded ordering seed
`9082026`. The user's focused-check policy was followed; no full-suite claim.

Passed:

```sh
flutter pub get --enforce-lockfile
flutter analyze --no-pub
# profiles/full:
flutter pub get --enforce-lockfile
flutter analyze --no-pub

flutter test test/ui/d_avatar_test.dart test/styleguide/avatar_examples_test.dart \
  test/image_decode_test.dart test/chat_message_tile_thread_preview_test.dart \
  test/topic_inbox_row_test.dart test/group_flair_test.dart \
  test/group_page_test.dart test/site_theme_app_test.dart \
  test/forum_search_clear_accessibility_test.dart test/d_button_adoption_test.dart \
  test/avatar_loader_test.dart test/media_pipeline_boundary_test.dart \
  test/voice_room_view_test.dart test/assignment_sheet_test.dart \
  test/assigned_group_view_test.dart test/event_card_test.dart \
  test/user_card_target_accessibility_test.dart \
  --no-pub --test-randomize-ordering-seed=9082026
# 250 passed.

# After exact Lucide artwork / explicit arbitrary-widget icon slot correction:
flutter test test/ui/d_avatar_test.dart test/styleguide/avatar_examples_test.dart \
  --no-pub --test-randomize-ordering-seed=9082026
# 15 passed; flutter analyze --no-pub also passed again.
```

Tests cover provider loading/error/ready, delayed fallback, late obsolete frames,
real local PNG decoding, stable identity/decorative semantics, badge dimensions,
SVG hiding, standalone count geometry, group size inference and override,
explicit dimensions, RTL overlap and narrow wrapping, 200% text, live themes,
menu keyboard selection/Escape/focus restoration and preview state preservation.
Downstream suites cover actual raster/SVG rejection/reporting, chat flair and
presence, group permissions, forum/rail theme integration, media request/cache
boundaries, Voice, Assign, Events and user-card keyboard access.

Touched Dart files were formatted and git diff --check passed. Root and full
profile pubspec locks, Flutter pin and runner configuration remain unchanged.

## Isolated native build

```sh
flutter build macos --debug --no-pub -t tool/avatar_review_main.dart
codesign --verify --deep --strict 'build/macos/Build/Products/Debug/Avatar Review 32e1.app'
```

The build temporarily sets a unique product name and Info.plist identity, then
restores the original runner files. Xcode's debug bundle setting emits a
warning because it defaults to org.discourse.native.dev; the actual built
Info.plist is explicitly verified as `org.discourse.avatarreview32e1`, name
`Avatar Review 32e1`, scheme `discourse-avatar-review-32e1`. Strict deep signature
verification passed. No normal Discourse app is launched or quit by this task.

## Native inspection — 2026-09-08, macOS 26.6.2 arm64

The coordinator explicitly granted the exclusive slot after Spinner. Inspected
source checkpoint above using the actual built app. Only the example catalogue
status changes from baseline to implemented after this verification; rendered
component/example/fixture behavior is unchanged.

- Production fixture: initial pending response displayed CN and forum monogram
  at stable 40px bounds; HTTP error retained the fallback; ready local PNG
  replaced it without a size jump. Clicking the actual ForumIcon/DButton action
  changed `Forum actions: 0` to `1`. Dark + RTL + 200% retained fixed adapter
  bounds, readable CN/LC, correct image clipping and trailing alignment.
- Official page in Chrome: inspected dark Sizes and Avatar Group with Icon,
  then light Badge with Icon. Compared actual circular bounds, 24/32/40 size
  ratios, 8px overlaps, 2px rings and tiny Lucide round-stroke plus with native
  light badges, dark groups and dark image/fallback sizes at 100% text.
  Native uses the configured site palette and local checker art, not upstream
  portraits. Screenshots have different capture bounds (native 1144×768,
  browser 1388×952); this is a visual/metric comparison, not a pixel-diff claim.
  Native preview widths were Fit and 360px; upstream desktop demo was about
  630px wide. These intrinsic avatar metrics do not depend on container width.
- Native badge series: observed dot, small hidden SVG, standard/large SVG,
  custom count and background rings in light and dark.
- Native groups: observed sm/default/lg, count and exact SVG-plus composition;
  Forest 360px + 200% + RTL + reduced motion retained readable complete rows.
  Arabic RTL example placed the first identity at the right and badge on the
  trailing side. No overflow strips or clipped controls appeared.
- Generic local-image example: invalid bytes changed `Image: ready` to
  `Image: error` and restored CN. Switching Forest to Plum retained that error
  selection and changed all live colors. Preview state was not reconstructed.
- Dropdown in Plum 360px + 200% RTL: click opened an unclipped menu; Settings
  changed the local message to `Settings selected`. The avatar retained its
  visible focus ring. Return reopened the menu from restored focus; Escape
  dismissed it and kept the focus ring. Button/Dropdown Menu visual ownership
  remains explicitly temporary and does not affect Avatar fidelity.

Evidence images in this directory:

| File | Captured state |
| --- | --- |
| production-dark-rtl-200.png | Actual AvatarImage and ForumIcon error fallbacks; local action count retained |
| reference-dark-sizes.png | Official 24/32/40 image size progression |
| reference-dark-group.png | Official group overlap and stroked plus |
| reference-light-badge.png | Official light badge with plus |
| native-light-badges.png | Native dot, SVG hiding, icon and count badge series |
| native-dark-groups.png | Native sm/default/lg/count/plus groups |
| native-forest-360-rtl-200.png | Preview settings plus large-text mirrored groups |
| native-forest-groups-full.png | Complete Forest group series and rings |
| native-generic-error.png | Invalid local bytes and restored fallback |
| native-plum-error-preserved.png | Same error selection after live palette change |
| native-plum-dropdown-open.png | Native menu inside narrow large-text RTL preview |
| native-dropdown-focus-restored.png | Settings result and focus after Return/Escape |
| native-dark-sizes.png | Native image and fallback sm/default/lg at 100% |
| native-arabic-rtl.png | Explicit Arabic initials/count/trailing badge |

Limitations: no iOS/Linux device run and no VoiceOver spoken-output verification.
The original fixture controls appeared in native AX. After entering the nested
styleguide, the main AX tree mostly exposed only the search field, although
native selection menus exposed their choices; visual coordinates and actual
keyboard actions completed the inspection. No global semantics, SDK or system
settings were changed. CUA occasionally rejected actions after an app-state
change; refreshed full state and fresh menu lookup resolved this. The initial
app selection took about 267 seconds; no artificial long wait was added.
Focus/identity/decorative semantics remain additionally covered by widget tests.

Closed only the created reference tab, restoring its initial dark theme first.
Quit only Avatar Review 32e1 via its own menu. The next global inventory briefly
reported it still running while termination completed; a subsequent global
`cua.getState` contained no app named Avatar Review 32e1 and no bundle identifier
org.discourse.avatarreview32e1. Reported that absence and released the desktop
slot to the coordinator before finalizing metadata. Other app processes were
left untouched. No real account changes occurred.

Final registration-only verification: `flutter test test/styleguide/avatar_examples_test.dart test/styleguide/styleguide_page_test.dart --no-pub --test-randomize-ordering-seed=9082026` passed 12 tests. Touched-file format check, git diff --check and exact unrelated-progress-row preservation checks passed.
