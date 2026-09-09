# Native Select isolated build

Source commit: `b6a1e7f736966ffc6c3923f353f7f007faa30e43`. Built with Flutter 3.47.2 / Dart 3.13.2 using `flutter build macos --debug --no-pub -t tool/native_select_review.dart`.

Review app: `/tmp/native-select-review-89bf/Native Select Review 89bf.app`.

Actual bundle name: Native Select Review 89bf; identifier: `org.discourse.nativeselectreview89bf`; URL scheme: `discourse-native-select-review-89bf`. Copied with ditto, ad-hoc signed; `codesign --verify --deep --strict` passes and signature identifier matches. Temporary name/Info overrides were restored; production native files are unchanged. Xcode reports its existing Debug build-setting identifier differs from the overridden Info identifier; the built Info and verified signature both contain the unique review identifier above.

All four artifacts have SHA-256 `81b0f4bf22da856792d5f6e43041f7fd4ea6fbf89961c23af84fa745ddfa3995`:

- `/Users/joffreyjaffeux/.codex/worktrees/89bf/discourse-native/.dart_tool/flutter_build/d12c069fb6c162628acd8878c3393661/app.dill`
- `/Users/joffreyjaffeux/.codex/worktrees/89bf/discourse-native/build/macos/Build/Products/Debug/App.framework/Versions/A/Resources/flutter_assets/kernel_blob.bin`
- `/Users/joffreyjaffeux/.codex/worktrees/89bf/discourse-native/build/macos/Build/Products/Debug/Native Select Review 89bf.app/Contents/Frameworks/App.framework/Versions/A/Resources/flutter_assets/kernel_blob.bin`
- `/private/tmp/native-select-review-89bf/Native Select Review 89bf.app/Contents/Frameworks/App.framework/Versions/A/Resources/flutter_assets/kernel_blob.bin`

Compiled lib/tool/test source equals the source commit after building. This evidence-only follow-up does not change compiled source. Build log: `/tmp/native-select-final-build.log`.

323 selected component, fixture, styleguide and production-owner tests passed; routed Chat notification integration test passed separately. Root and full-profile analysis passed. Pins and lockfiles remain unchanged.

Status: **awaiting_slot**, progress **in_progress**. No app launch or CUA occurred. Reference-rendered/native visual and accessibility inspection remains pending coordinator desktop access. The fixture uses local fake account/API data and simulated Voice media adapters.
