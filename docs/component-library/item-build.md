# Item native review bundle — awaiting_slot

Final source commit: `e792c5156c87715d2db5549ff5d35928e0e3b46e`.
The later handoff commit changes documentation/progress only.

Bundle:
`/Users/joffreyjaffeux/.codex/worktrees/82f4/discourse-native/build/macos/Build/Products/Debug/ItemReview82f4.app`

Verified from its actual Info.plist:

- Name/executable: `ItemReview82f4`
- Bundle identifier: `org.discourse.itemreview82f4`
- URL scheme: `discourse-item-review-82f4`
- Entrypoint: `lib/item_review_main.dart`

The fixture mounts real production TagDirectoryRow and AssignmentDetailRow,
with local data and callbacks. Its Styleguide button opens the actual full
component styleguide; search for Item. Review both surfaces after receiving the
coordinator's desktop slot. Nothing was launched in this task.

## Build and signature

`flutter build macos --debug --no-pub -t lib/item_review_main.dart` succeeded.
A first attempt failed because the unique identifier had no development profile.
The successful build temporarily disabled Xcode signing with
`CODE_SIGNING_ALLOWED = NO`, then used local ad-hoc signing:

```sh
codesign --force --deep --sign - \
  --entitlements macos/Runner/DebugProfile.entitlements \
  build/macos/Build/Products/Debug/ItemReview82f4.app
codesign --verify --deep --strict --verbose=2 \
  build/macos/Build/Products/Debug/ItemReview82f4.app
```

Verification returned **valid on disk** and **satisfies its Designated Requirement**.
No provisioning profile, signing account, App Store Connect or release change
was made. The build used only this isolated checkout, never the user's real
application build directory.

The temporary identity substitutions touched AppInfo.xcconfig, Info.plist and
project.pbxproj (Runner scheme was inspected and unchanged). Original bytes were
restored in a finally block. Override hashes are saved in
`reference/item/build.json`. The local build helper and log remain at
`/tmp/item-review-build-82f4.py` and `/tmp/item-review-82f4-build.log`.

## Kernel and source equality

Both the source build App.framework and the copied bundle App.framework contain
identical `Versions/A/Resources/flutter_assets/kernel_blob.bin` bytes:

`7f7f633347d1a22adc56397fec4be1298837c0702253676fef1662d46991b596`

Verified after signature creation:

- `git diff e792c515 -- lib pubspec.yaml macos` is empty.
- Flutter pin and root/full/voice lockfiles are identical to base `402fe578`.
- Working tree was clean before this documentation-only handoff update.

## Checks and remaining gate

- Flutter 3.47.2; root/full enforced-lockfile resolution passed.
- Root/full static analysis passed after the final correction.
- Original 47-test focused run covered Item, examples, fixture, TagsPage,
  AssignmentSheet and the styleguide shell. Final correction passed 34 tests
  across Item, examples, fixture and both app migration suites (seed 9092026).
- The correction proves large text and explicit unlimited notes override an
  inherited menu clamp. Existing checks prove focus painting stays exterior,
  child action isolation, form-state retention, token changes, RTL, geometry,
  native list roles and local production callbacks.

**in_progress / awaiting_slot**: no browser/native slot, app launch, actual
reference-rendered comparison, VoiceOver or device test has occurred. Passing
widget tests and strict signature validation do not establish visual parity.
Button/Dropdown dependent example visuals and additional Events row candidates
remain explicit coordinator reconciliation items in `item.md`.
