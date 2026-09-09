# Native Select isolated build

Source commit: `f9baeaa86c2bd88058ab815687543587aeec5296`. Built with Flutter 3.47.2 / Dart 3.13.2 using `flutter build macos --debug --no-pub -t tool/native_select_review.dart`.

Review app: `/tmp/native-select-review-89bf/Native Select Review 89bf.app`.

Actual bundle name: Native Select Review 89bf; identifier: `org.discourse.nativeselectreview89bf`; URL scheme: `discourse-native-select-review-89bf`. Copied with ditto, ad-hoc signed; `codesign --verify --deep --strict` passes and signature identifier matches. Temporary name/Info overrides were restored; production native files are unchanged. Xcode reports its existing Debug build-setting identifier differs from the overridden Info identifier; the built Info and verified signature both contain the unique review identifier above.

All four artifacts have SHA-256 `bb7dca4c9c8906921f677cc834ff2b2bbe1990f4e29009a3b8144cedf1de8a37`:

- `/Users/joffreyjaffeux/.codex/worktrees/89bf/discourse-native/.dart_tool/flutter_build/d12c069fb6c162628acd8878c3393661/app.dill`
- `/Users/joffreyjaffeux/.codex/worktrees/89bf/discourse-native/build/macos/Build/Products/Debug/App.framework/Versions/A/Resources/flutter_assets/kernel_blob.bin`
- `/Users/joffreyjaffeux/.codex/worktrees/89bf/discourse-native/build/macos/Build/Products/Debug/Native Select Review 89bf.app/Contents/Frameworks/App.framework/Versions/A/Resources/flutter_assets/kernel_blob.bin`
- `/private/tmp/native-select-review-89bf/Native Select Review 89bf.app/Contents/Frameworks/App.framework/Versions/A/Resources/flutter_assets/kernel_blob.bin`

Compiled lib/tool/test source equals the source commit after building. This evidence-only follow-up does not change compiled source. Build log: `/tmp/native-select-queue-build.log`.

Refreshed after the browser correction: 155 impact-focused tests and two font-loaded render tests passed. The prior 323-test migration suite and routed Chat notification integration test also passed. Root and full-profile analysis passed. Pins and lockfiles remain unchanged.

Status: **awaiting_slot**, progress **in_progress**. Browser-only comparison was completed and the slot released with original dark theme/viewport restored; details in native-select-review.md. No native app launch or native CUA occurred. Native visual/device/VoiceOver inspection remains pending coordinator desktop access. The fixture uses local fake account/API data and simulated Voice media adapters.

## Pinned-main merge queue refresh

Integrated main `e612ad7b47413fa890b35ae3b55a6f6d37b08cf7`. Final Button/Badge/Input/Radio Group/Checkbox sources and all non-Native-Select progress rows match pinned main. Plain selectors retain their migrations and rich category/search picker boundaries. Root/full analysis passed. Integration run:327 passed, one obsolete100px bookmark test-host overflow; adjusted that test host to120px for final touch targets, then all24 bookmark tests passed. No production layout change.

Copied app signed with restricted-free debug entitlements; removed development push entitlement, retained sandbox, allow-jit, client/server network, user-selected files, audio-input and camera. Signed read-back exactly equals `/tmp/native-select-review-89bf/debug-entitlements.plist`; read-back saved at `/tmp/native-select-review-89bf/signed-entitlements.plist`. No `com.apple.developer.*` keys, strict deep signature verification passes. No provisioning profile update or release writes. No browser/CUA/native launch attempted during integration.
