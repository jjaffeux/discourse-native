# Marker native review queue

## Current integration build (supersedes the earlier bundle)

Merged pinned main `e612ad7b47413fa890b35ae3b55a6f6d37b08cf7` into Marker.
Executable source/merge commit: `ba156a2ce378787c25fdd4a8910fbf86390c4a8a`.
All non-Marker progress rows match pinned main, and all17 merged component
owners plus coordinator Group/Sidebar/Topic Inbox fixes are preserved.
Only Marker and its existing StreamDaySeparator adoption differ under
component/shell/plugin source paths. Static dates remain non-live; status is
opt-in. Narrow large-text separator wrapping remains covered.

- Current bundle: `/tmp/marker-review-3d0a-ba156a2c/build/macos/Build/Products/Debug/Marker Review ba156a2c.app`.
- Bundle ID: `org.discourse.markerreview.ba156a2c`; scheme: `discourse-marker-review-ba156a2c`.
- Git archive of the exact source commit; all1350 tracked lib/packages/pubspec/pin files byte-identical.
- Three-way compiler app.dill / built framework / copied bundle kernel SHA256: `a290d26bba0b82caefbc0645fd42c0e1725b3ac54a550bd44139e4f29279bc83`.
- Explicit temporary debug/JIT entitlements contain exactly `com.apple.security.cs.allow-jit`, `com.apple.security.cs.allow-unsigned-executable-memory`, and `com.apple.security.cs.disable-library-validation`, all true. Signed readback via `codesign -d --entitlements :-` parsed and matched this exact dictionary; no restricted entitlement or production identity remains.
- Ad-hoc signing and `codesign --verify --deep --strict --verbose=2` passed (valid on disk; satisfies Designated Requirement).
- Source and signature report: `/tmp/marker-ba156a2c-provenance.json`; build/sign logs: `/tmp/marker-ba156a2c-build.log`, `/tmp/marker-ba156a2c-sign.log`.
- Root/full enforced-lockfile resolution and static analysis passed; no production runner/pin/lockfile changes. Touched formatting and diff check passed.
- Same focused command below passed116 tests, seed2335286571 (`/tmp/marker-integration-tests.log`). Additional static-versus-live assertion passed all13 Marker tests, seed2483898728 (`/tmp/marker-integration-static-tests.log`).

Still **awaiting_slot**, **in_progress**, and not mergeable. Mac locked and
browser access separately denied by admin policy; no CUA, browser navigation,
native launch, retry or workaround attempted. Required reference/native review
remains outstanding. The checklist below applies to this new bundle.

## Earlier build evidence (historical)

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
