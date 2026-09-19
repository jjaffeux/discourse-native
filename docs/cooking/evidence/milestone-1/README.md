# Milestone 1 host evidence

Recorded on 2026-09-19 in `/Users/joffreyjaffeux/.codex/worktrees/b845/discourse-native`, branch `codex/cooking-m1-runtime`, starting commit `836f22900bfe091bddc62b9959802641e605188a`. macOS 26.6.2 ARM64, Flutter 3.47.4, Dart 3.13.3. Files contain complete command output; `.txt.gz` files can be read with `gzip -dc FILE`. Empty configuration output files represent successful quiet commands.

## Exact commands

From `packages/discourse_cooking`:

```sh
dart pub get --enforce-lockfile
dart format --output=none --set-exit-if-changed lib/src/contracts.dart lib/src/service.dart lib/src/native_runtime.dart lib/discourse_cooking.dart test bin hook tool
dart analyze --fatal-infos
dart test --test-randomize-ordering-seed=1187662061
dart run bin/benchmark.dart
dart build cli --target=bin/benchmark.dart --output=build/benchmark
./build/benchmark/bundle/bin/benchmark
```

Outputs: `package-pub-get.txt`, `package-format.txt`, `package-analyze.txt`, `package-tests.txt`, `benchmark-jit.json`, `aot-build.txt`, `benchmark-aot.json`. The targeted native boundary run was `dart test test/src/native_runtime_test.dart`, captured in `native-boundary-tests.txt` (it is also included in the complete package suite).

From `packages/discourse_cooking/js`:

```sh
npm ci --ignore-scripts
npm run verify
npm test
```

Outputs: `npm-ci.txt`, `js-verify.txt`, `js-tests.txt`.

From the repository root:

```sh
python3 packages/discourse_cooking/tool/vendor_quickjs.py
flutter test test/offline_cooking_runtime_test.dart
flutter analyze --no-pub lib test/offline_cooking_runtime_test.dart
flutter analyze --no-pub
flutter test --no-pub --test-randomize-ordering-seed=67214
flutter build ios --simulator --debug --no-codesign
flutter build macos --debug --config-only
xcodebuild build -workspace macos/Runner.xcworkspace -scheme Runner -configuration Debug -derivedDataPath build/macos-cooking-ci CODE_SIGNING_ALLOWED=NO
```

Outputs: `native-provenance.txt`, `flutter-native-smoke.txt`, `focused-root-analyze.txt`, `root-analyze.txt`, `root-tests.txt.gz`, `root-ios-build.txt`, `root-macos-config.txt`, `root-macos-build.txt.gz`.

From `profiles/full`:

```sh
flutter analyze --no-pub
flutter build ios --simulator --debug --no-codesign
flutter build macos --debug --config-only
xcodebuild build -workspace macos/Runner.xcworkspace -scheme Runner -configuration Debug -derivedDataPath build/macos-cooking-ci CODE_SIGNING_ALLOWED=NO
```

Outputs: `compatibility-analyze.txt`, `compatibility-ios-build.txt`, `compatibility-macos-config.txt`, `compatibility-macos-build.txt.gz`.

Native frameworks were also verified present in the outputs:

```text
build/ios/iphonesimulator/Runner.app/Frameworks/discourse_cooking.framework/discourse_cooking
profiles/full/build/ios/iphonesimulator/Runner.app/Frameworks/discourse_cooking.framework/discourse_cooking
build/macos-cooking-ci/Build/Products/Debug/Discourse.app/Contents/Frameworks/discourse_cooking.framework/Versions/A/discourse_cooking
profiles/full/build/macos-cooking-ci/Build/Products/Debug/Discourse.app/Contents/Frameworks/discourse_cooking.framework/Versions/A/discourse_cooking
```

The native agent's exact C cross-compile driver/output and native initialization/interrupt smoke are in `native-cross-compile.txt` and `native-smoke.txt`. These files explicitly identify transcribed tool output; the original agent did not persist log files.

## Baseline comparison

The baseline is an unmodified `git archive HEAD` export of the starting commit inside this assigned worktree's ignored `build/cooking-baseline`. No main checkout or reference source was modified. Commands:

```sh
mkdir -p build/cooking-baseline
git archive HEAD | tar -x -C build/cooking-baseline
cd build/cooking-baseline
flutter pub get
flutter test --no-pub --test-randomize-ordering-seed=67214 test/shell_rebuild_isolation_test.dart test/composer_upload_panel_test.dart test/ui/d_mermaid_test.dart
flutter test --no-pub --test-randomize-ordering-seed=67214
```

Complete baseline outputs and a comparison of failing test names are retained alongside the candidate output. These host-wide root failures are not a successful CI gate; see the milestone document for the final counts and limits.

Both full runs stopped progressing at the same user-card test. Before interruption candidate was `+11599 ~7 -288`, baseline `+11598 ~7 -288`; `baseline-comparison.json` records identical completed failure names (zero new failures). Sent `kill -INT 79606 81038` to the two observed Flutter test processes. Complete pre-interrupt snapshots are `root-tests-before-interrupt.txt.gz` and `baseline-tests-before-interrupt.txt.gz`; complete final output is `root-tests.txt.gz` and `baseline-root-tests.txt.gz`. Final summaries include the interrupted test and show 289 failures. These are incomplete failing runs, never a passing gate.
