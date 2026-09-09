# Marker native review queue

Status: **awaiting_slot**, component remains **in_progress**. No browser/native
focus has been used. Mac was locked throughout implementation; neither this
build nor widget tests establish native accessibility or visual parity.

## Exact build provenance

- Executable source: `4e48ba4597a5bbf4dbf3fb7bb55a16c8117cee18` (implementation
  `c9dffe432b2afc668c2af7aafd9dfc79ccb3cd66`, plus shimmer alpha correction).
- Isolated source: `/tmp/marker-review-3d0a-c9dffe43`. Created with git archive
  of implementation commit and updated with the final committed Marker file.
  All **1340 tracked lib/packages/pubspec/pin files** compared byte-identical
  with final worktree. Archive has no Git metadata; external byte comparison
  above is the source authority rather than the app's About Git stamp.
- Build: `flutter pub get --enforce-lockfile`, then
  `flutter build macos --debug --no-pub --target lib/marker_review_main.dart`.
- Bundle: `/tmp/marker-review-3d0a-c9dffe43/build/macos/Build/Products/Debug/Marker Review 3d0a.app`.
- ID: `org.discourse.markerreview3d0a`; URL scheme:
  `discourse-marker-review-3d0a`. Product name is `Marker Review 3d0a`.
- Only the temporary native runner changed product/ID/scheme/signing. Its unused
  push entitlement was removed and ad-hoc signing enabled. Worktree runner,
  Flutter3.47.2, pins/lockfiles and user's real app build remained unchanged.
- SHA256 of all three artifacts (compiler app.dill, built App.framework kernel,
  copied app-bundle kernel):
  `056c1ff41d714c630b966e954b39879d6c9fc78dd3bc41e05520edb4d57067fa`.
- `codesign --force --deep --sign - --entitlements <temporary DebugProfile.entitlements> <bundle>`
  followed by `codesign --verify --deep --strict --verbose=2 <bundle>` passed:
  valid on disk; satisfies its Designated Requirement.
- Logs: `/tmp/marker-native-build.log`, `/tmp/marker-sign.log`,
  `/tmp/marker-provenance.txt`. Final documentation-only commit does not change
  compiled source equality.

## Verification performed

Root/full locked resolution and root/full static analysis passed. Touched
formatting and `git diff --check` passed. Focused command:

```
flutter test --no-pub test/d_marker_test.dart test/topic_day_separator_test.dart test/chat_stream_test.dart test/chat_channel_view_lifecycle_test.dart test/styleguide/styleguide_page_test.dart --test-randomize-ordering-seed=random --reporter expanded
```

115 passed; seed109839089; `/tmp/marker-focused.log`. Final alpha-only correction
then passed all13 Marker tests and root/full analysis, with
`/tmp/marker-alpha-test.log`. These cover source geometry, intrinsic separator
lines, keyboard/pointer/disabled/link/status semantics, decorative Spinner,
lifecycle/reduced motion, local example actions, live theme updates,220px RTL
200% wrapping, and actual Topic/Chat date navigation/pinned-date regressions.

## Inspection to perform after explicit coordinator grant

1. Compare official base-nova Marker at matching384px width and100% text with
   all four native Marker styleguide groups: default light/dark; 14/20 text,
   icon strokes/size/gaps, separator balance/12px gap, border29px height,
   stacking, underline and shimmer color/sweep. Source URLs and hashes are in
   marker-reference.md. Inspect shimmer in motion and reduced motion.
2. Native styleguide Light/Dark/Plum/Forest,360px,200%,RTL, retained local
   complete/restart and link/revert state; Tab/Shift+Tab,Return/Space, disabled
   action, outside-only focus and mouse hover. Verify live theme changes.
3. Fixture landing page mounts real StreamDaySeparator (used by Topic/Chat),
   with normal, floating and no-divider dates. Change palette,width,text,RTL;
   click label and rule separately, verify jump counter changes only for date.
   Check fixed44px timeline slot and floating background/hover/tooltip.
4. Inspect large-text fit and return from styleguide to retained fixture
   state. Close only this unique review app and release the slot.

No iOS/Linux device or spoken VoiceOver test was run. The app was built and
signed, never launched. Exact raster/underline/shimmer parity remains unverified.
