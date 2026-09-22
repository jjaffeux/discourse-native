# Groups directory layout review — 2026-09-22

The directory uses the supplied screenshot's single-column layout on desktop
and mobile: heading, group filter and count, divided rows, circular group
identity, top-aligned membership status, optional description, and member
avatars/count. Search is available from the heading and group creation remains
available to authorized users. All controls use the existing Native UI kit.

Member previews request at most four members as rows are built, cache per page
visit, and skip hidden/empty groups. Account changes retire cached previews;
late responses are checked against both the controller lifecycle and page owner.
Preview failures leave the directory and member count usable.

Verification:

- 129 focused tests passed across groups page, controller, host, boundary, and
  member-menu ownership suites.
- The updated mobile header and control adoption checks passed; 33 focused
  page/host/adoption tests passed again on the integration branch.
- `flutter analyze --no-pub` and `git diff --check` passed.
- Widget coverage includes 390/700/1400 px layouts with iOS/Android/macOS theme
  overrides, 312 px RTL at 200% text, filter clearing, search retention,
  keyboard activation, pagination, preview caching and stale-account rejection.
- Built `tool/groups_layout_review_main.dart` for macOS, copied to an isolated
  ad-hoc-signed app, and inspected desktop/390 px mobile layouts in dark/light
  palettes. Verified My groups filtering (7 → 4), search (4 → 1), clearing,
  row activation, and the Avatar styleguide. No overflow was observed.

Mobile layouts were inspected in the macOS fixture and widget tests; this was
not an iOS or Android device run. Native inspection used the same page/component
source as the integration candidate; intervening main changes were unrelated.
