# Item native review bundles

## Corrected independent-review bundle

The independent reviewer rebuilt after the native-observed large-text overflow
fix at source `fcc26238982fb062a84b4f964995d7026e547af7`:

`/Users/joffreyjaffeux/.codex/worktrees/d14a/discourse-native/build/macos/Build/Products/Debug/ItemReviewD14aFinal.app`

Actual Info.plist identity: `ItemReviewD14aFinal`, bundle identifier
`org.discourse.itemreviewd14afinal`, URL scheme
`discourse-item-review-d14a-final`. Build and copied App.framework kernels both
have SHA256 `b792631873ef9e75576a154432c7f7e6eb9c6d0d9915843c2f945fa2d4675013`.
Runner overrides were restored; source and dependency pins equal the recorded
source. A deep strict ad-hoc signature passed with only the debug/JIT and network
entitlements listed below.

The serialized native pass confirmed both real AssignmentDetailRow notes remain
fully visible at 200% text in RTL/dark mode, without ellipsis, and that the second
row still dispatches `Edit assignment 2`. See
`reference/item/review-build.json` for compact provenance. The earlier integrated
bundle is retained below as historical pre-fix evidence.

## Earlier integrated bundle

Current executable source: `68402409ccc314b6e9b624cf1d86b16531ccdcc4`.
Pinned main: `e612ad7b47413fa890b35ae3b55a6f6d37b08cf7`, integrated through
merge `1462873c`. The subsequent handoff commit changes only evidence/progress.

Bundle:
`/Users/joffreyjaffeux/.codex/worktrees/82f4/discourse-native/build/macos/Build/Products/Debug/ItemReview82f4Integrated.app`

Verified from actual Info.plist:

- Name/executable: `ItemReview82f4Integrated`
- Bundle identifier: `org.discourse.itemreview82f4integrated`
- URL scheme: `discourse-item-review-82f4-integrated`
- Entrypoint: `lib/item_review_main.dart`

The fixture mounts actual production TagDirectoryRow and AssignmentDetailRow
with local data and callbacks. It uses final controlled Checkbox settings and
opens the actual styleguide through the final Button. Item examples now use final
Button outline/small and accessible round icon-only outline/ghost actions, plus
Badge role composition. The Form regression uses final DInput. There is no
reference radio choice to replace. This earlier bundle predates the accepted
Dropdown Menu composition, which was verified by focused widget tests in the
final latest-main candidate without repeating the unchanged Item native pass.

## Build, signature and signed entitlement readback

`flutter build macos --debug --no-pub -t lib/item_review_main.dart` succeeded.
The build temporarily supplied the unique identity and
`CODE_SIGNING_ALLOWED = NO`, then restored original runner bytes in a finally
block. No profile lookup retry, account action or provisioning change occurred.

Signed with an explicit local plist instead of the real app's entitlement file:

```sh
codesign --force --deep --sign - --options runtime \
  --entitlements /tmp/item-integration-82f4-debug.entitlements \
  build/macos/Build/Products/Debug/ItemReview82f4Integrated.app
codesign -d --entitlements :- \
  build/macos/Build/Products/Debug/ItemReview82f4Integrated.app
codesign --verify --deep --strict --verbose=2 \
  build/macos/Build/Products/Debug/ItemReview82f4Integrated.app
```

Signed readback exactly equals these true-valued keys:

- `com.apple.security.cs.allow-jit`
- `com.apple.security.cs.allow-unsigned-executable-memory`
- `com.apple.security.cs.disable-library-validation`
- `com.apple.security.get-task-allow`
- `com.apple.security.network.client`
- `com.apple.security.network.server`

The main app, contained frameworks and debug dylibs were read back separately:
no restricted application identifier, team identifier, APNs or developer
entitlement was present. No embedded provisioning profile exists. Deep strict
verification returned **valid on disk** and **satisfies its Designated Requirement**.
The exact signed dictionaries, override hashes, path and verification output
are in `reference/item/integration-build.json`; the explicit plist is
`reference/item/integration-debug.entitlements`.

The build helper/log remain at `/tmp/item-integration-build-82f4.py` and
`/tmp/item-integration-82f4-build.log`. Only this worktree's build directory was
used. No app was launched, and no CUA/browser access or policy retry was attempted.

## Kernel and source equality

Build and copied App.framework
`Versions/A/Resources/flutter_assets/kernel_blob.bin` match exactly:

`cf0a1efc46876ee29e0fc93fcee132e6b14977e82d0f1dd725c472b55df48122`

After signing and runner restoration:

- `git diff 68402409 -- lib pubspec.yaml macos` is empty.
- Flutter pin and root/full/voice lockfiles equal pinned main `e612ad7b`.
- All non-Item progress rows equal pinned main, preserving all 17 merged rows.
- Group, Sidebar, styleguide shell, Topic Inbox and keyboard-navigation files
  equal pinned main. Shared exports/registrations preserve every merged owner.

## Integration checks and remaining gate

Root and full-profile `flutter analyze --no-pub` pass after final source changes.
The initial integration run passed the Item, styleguide-example, TagsPage and
AssignmentSheet suites; only the fixture test failed when full-width Checkbox
settings pushed its tap target off-screen. Controls were bounded and the test
now settles scrolling before tapping. The final Item/fixture run passed 11 tests,
including the new nested final Checkbox pointer/Space isolation check. No
unrelated full suite was run; no generic Item or merged-owner implementation was
changed during this bounded integration.

Formatting and `git diff --check` pass. Existing tag navigation/request/lazy-list
and assignment permission/accessibility tests remain green. Final Button nested
activation and final Input Form retention through large-text RTL reflow pass.

**in_progress / awaiting_slot**: actual reference rendering and native fixture
plus styleguide review are still required. Mac remains locked; browser access is
separately denied by admin-policy verification. No CUA/browser/native launch,
policy retry/workaround, VoiceOver or device test was performed. Dropdown Menu
composition and retained Events row candidates still need coordinator review.

Historical pre-integration source/kernel evidence remains in
`reference/item/build.json`; use the integrated bundle above for future review.
