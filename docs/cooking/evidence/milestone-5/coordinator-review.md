# Milestone 5 coordinator acceptance

Implementation: `1c709b8c839047a4718ec3b9c963e4401a9b7b9f`; reader correction: `2297a10bb255dea1a2c86a25f1dba806d9f7b04c`, based on local main `ea9412fe234742d9134b429ab11872f8f54ba72e`.

Implemented in the coordinator task with bounded collaborators after the user's workflow change. No composer preview UI is included. Chat is the completed immediate-display consumer; post cooking is exposed through the shared host, while topic/reply insertion continues to use the normal server response.

## Independent review

The coordinator checked the generated bundle and eight newly vendored files against the pinned Discourse repository, inspected Native ownership/settings and consumer boundaries, ran the complete root suite, and reviewed the contributors' implementation. Separate collaborators reviewed compiler profile isolation and renderer concealment. The final artifact manifest was checked against the built files.

Review found and corrected actual hidden descendants restored inside forged Chat/code wrappers, an outer-gallery path into closed disclosures, poll title/option/ranked-result accessibility labels exposing concealed text, and details summaries flattening concealed text. Visible and concealed descendants are exercised through the actual worker and Native renderer, including independent reveal/vote behavior. The initial full suite failure is retained as historical evidence, not a successful final result.

## Actual checks

- Final complete root suite: **12,071 passed, 7 skipped, 0 failed** in 5m18s, randomized seed 67214, on correction commit `2297a10bb255dea1a2c86a25f1dba806d9f7b04c`.
- 183 native package tests and 150 JavaScript tests passed. The shared post corpus has 38 fixtures, including an independent UTF-8 JSON MD5 oracle for pinned poll option IDs and outer/nested Chat profile exclusions.
- Final focused reader checks: 68 lightbox/spoiler tests and 47 poll/details tests passed. These counts overlap the full suite.
- Fatal-infos analysis passed for the final root, full wrapper, Voice and compiler package; 1,890 application Dart files and the separate compiler package passed formatting without changes.
- Root, full wrapper, Voice and compiler package dependencies resolved with enforced lockfiles; tracked lockfiles were unchanged.
- Reproducible bundle check passed: 2,438,567 bytes, SHA-256 `0b445bf11e88a702f9eb0d9e5a9748977270f5d585cb9db21c92fba71d6c2529`. Eight new pinned vendor files and 21 native source hashes verified.
- Standalone macOS ARM64 AOT benchmark built and executed with the final compiler package. At 100 warm samples, startup was 415.531 ms, median 34.621 ms, p95 36.572 ms, and QuickJS allocated 8,312,080 bytes. Concurrent validation was running; these are diagnostic samples, not controlled performance or whole-Chat latency guarantees.
- All four final root/full iOS simulator Debug and unsigned macOS Debug builds passed on correction commit `2297a10bb255dea1a2c86a25f1dba806d9f7b04c`. The coordinator independently verified the clean source commit, every kernel and native binary size/hash, embedded compiler hash, and five exports in each packaged architecture (iOS arm64+x86_64; macOS arm64).

## Commands and evidence

The root suite used `flutter test --no-pub --test-randomize-ordering-seed=67214 --reporter expanded`. Analyzers used `dart analyze --fatal-infos`. The root format gate covered `lib test integration_test tool packages/discourse_voice/lib packages/discourse_voice/tool profiles/full/lib`; compiler formatting was checked separately.

Compiler validation used the package's checked-in Node/native test suites and reproducible generation checks. `python3 packages/discourse_cooking/tool/vendor_quickjs.py` verified native provenance. AOT execution used `dart build cli --target=bin/benchmark.dart --output=build/m5-benchmark`, then the generated executable.

Apple validation used an isolated checkout to avoid sharing Flutter native-asset staging with the root tests. Both root and full profiles used `flutter build ios --simulator --debug --no-codesign --no-pub`, `flutter build macos --debug --config-only --no-pub`, and unsigned Debug `xcodebuild` with the Runner workspace and scheme. Initial builds used the implementation commit; final builds used the reader correction commit. See the artifact manifests for exact paths, kernel hashes, native binaries and verified exports. Retained compressed build/test logs are ordinary gzip text. `manifest.json` records the size and SHA-256 of each evidence file.

## Limits and merge

- Ruby plugins require explicit bundled portable modules. Server authorization, database state and uncached remote enrichment remain server-owned. Cooking initiates no lookup, cooking, resolver or onebox request.
- Current context lacks group-member timezone and livestream attendance snapshots; fallback behavior is documented in the milestone architecture. Rendering media and normal send/edit/upload transport retain their existing network paths.
- Inline spoilers use a Native disclosure. Details summary spoilers use a concealed-content label. Poll disclosures have independent controls; the existing bare Native radio activates through its painted indicator and keyboard, but its blank surrounding area is not a working touch target. No UI kit extension was made.
- macOS native worker and AOT execution were exercised. Apple packaging was built and inspected, not tested as physical-device interaction. Linux CI is configured but was not run locally. Android/Windows remain planned; web is unsupported.
- Final integration is a fast-forward from the main checkout after verification. No push is authorized. The consolidated implementation report records the accepted main commit after the merge and preserves earlier milestone results.
