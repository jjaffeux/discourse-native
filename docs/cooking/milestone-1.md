# Offline cooking milestone 1

This milestone supplies `packages/discourse_cooking`, a production runtime foundation with a typed Dart request/result boundary, a pinned Discourse JavaScript closure, and a persistent worker isolate. The root application depends on the package, but no chat/composer consumer is wired yet. Cooked HTML remains provisional; later integration must reconcile with normal send/MessageBus HTML without issuing another cook request.

## Architecture and ownership

`OfflineCookingService.cook(CookingRequest)` sends one serialized request to its worker and receives one result. `CookingProfile.post` and `.chat` explicitly select the profile. `CookingSnapshot` copies and recursively freezes finite JSON metadata for the site/account: settings, uploads, hashtags, custom emoji/translations, oneboxes/inline oneboxes, topics and avatars. Site/account identities travel with every request. There are no runtime callbacks into account services, Dart per-token callbacks, global account stores, or cache keyed only by raw text.

The worker owns one persistent QuickJS-NG VM and loads the bundle once. Each cook constructs a fresh Discourse engine/options instance; temporary onebox context is cleared in `finally` and the upstream emoji translation singleton is reset before/after every request. A native evaluation error destroys the VM; the next request creates a fresh VM. The public package exports only contracts/service, not arbitrary JavaScript evaluation. Call `start()` to prewarm, `cook()` to lazily start, and await idempotent `dispose()` when the application service is released. Startup/transport failure leaves that service unavailable; construct a new service to retry.

Synchronous FFI evaluation happens exclusively in the worker. Wrapping `evaluate` in `Future.value` would still block its calling isolate and is not used. The native adapter has no Flutter channels and uses Dart native-asset build hooks, compiling the same vendored C engine for native targets. This avoids runtime downloading or relying on a reference checkout.

### Limits and failures

Default limits are 65,536 raw UTF-16 code units, 262,144 serialized UTF-8 request bytes, 1,048,576 serialized result bytes, 64 MiB QuickJS heap, 1 MiB JS stack, four admitted requests, and 250 ms native execution per cook. Bundle initialization has a separate 10-second deadline. Structural preflight bounds serialization work and depth; the immutable snapshot constructor rejects nesting beyond 32 levels, more than 65,536 nodes/keys, or more than 262,144 total string code units with `ArgumentError` before copying excess context. Context producers must select relevant metadata rather than passing entire site caches; these constructor validation errors precede a cook request and cannot themselves return cooked text. Queue saturation rejects immediately. Input, output, execution, initialization, engine, disposal and transport failures resolve to escaped readable text, truncated to 8,192 code units, with a typed failure and no raw error details in the UI.

The native monotonic interrupt handler enforces the deadline inside the interpreter; the Dart watchdog covers worker/transport failures and bounded queueing. `Atomics.wait` is disabled so it cannot block outside interpreter polling. No fetch, XMLHttpRequest, sockets, filesystem, process, dynamic module loader, generic native bridge, timers or asynchronous host job loop are installed. QuickJS language intrinsics alone remain available. Memory measurements report QuickJS allocated heap bytes, not complete process RSS.

Normal disposal sends a stop message and awaits native destruction after bounded queued work. A native finalizer protects abnormal worker termination; Dart guarantees finalization by isolate-group shutdown, not immediately when an individual worker is killed. Thus catastrophic transport/watchdog termination can delay reclamation until GC/group shutdown. An FFI/native memory-corruption defect is outside an in-process JS sandbox's guarantees.

## Pinned sources and reproducibility

Discourse is pinned to `07a0e7b94717b45207749578df1f0bd2dd4d12e1`, initially copied read-only from `/Users/joffreyjaffeux/Code/pr-discourse`. That absolute path is not used by the application. `js/provenance.json` records SHA-256 for every copied upstream source, the upstream pnpm lock, build/reference adapters and chat profile source. The source tree keeps individual core feature modules and the actual spoiler-alert plugin module unchanged. Local behavior replacements are separate files under `js/src/`.

QuickJS-NG is pinned to v0.17.0, commit `6d46d07d04041b40f4f49eaa7fdebe44c314c699`. `vendor/quickjs/PROVENANCE.json` records archive and per-file hashes. The build excludes `quickjs-libc.c`; no standard-library bindings or module-loader functions are registered. `hook/build.dart` builds only the engine and small reviewed C shim. `lib/src/native_runtime.dart` describes the real synchronous API, error categories, lifetime and memory accounting.

`js/package-lock.json` pins npm dependencies. `js/build.mjs` verifies upstream hashes, resolves explicitly allowed Discourse imports, bundles for a neutral environment, and emits `assets/cooking.js`, a Dart source constant, dependency notices and a manifest of every build input. `npm run verify` rebuilds and compares exact generated output. Builds use bundled source and installed locked tools; only dependency installation/update needs network access.

Discourse's bundled source is GPL-2.0-only and retains its complete license. This package does not relicense it under the root project's MIT license. `js/NOTICE.txt` includes the bundled npm notices; QuickJS retains its MIT notice. The reproducibly generated package-root `LICENSE` combines complete upstream terms so Flutter's package license aggregation can include them in application distributions. Distribution must preserve the applicable upstream terms and corresponding source. The JavaScript is readable source, not engine-specific bytecode.

From the repository root:

```sh
(cd packages/discourse_cooking && dart pub get --enforce-lockfile)
npm ci --prefix packages/discourse_cooking/js
npm run verify --prefix packages/discourse_cooking/js
npm test --prefix packages/discourse_cooking/js
python3 packages/discourse_cooking/tool/vendor_quickjs.py
(cd packages/discourse_cooking && dart analyze --fatal-infos)
(cd packages/discourse_cooking && dart test)
(cd packages/discourse_cooking && dart run bin/benchmark.dart)
flutter test test/offline_cooking_runtime_test.dart
```

For a bundled standalone AOT program use `dart build cli --target bin/benchmark.dart --output <directory>` from the package, then run `<directory>/bundle/bin/benchmark`. `dart compile exe` does not execute native-asset hooks and must not be used for this distribution. See the package JS README and native vendor tool for intentional version updates; review fixture differences and regenerated provenance together.

## Final HTML trust and parity scope

Upstream sanitization runs before restoring `html_raw` hoists. Consequently it does not establish final output trust. The local `final-sanitize.js` applies a second, closed allowlist to the fully rendered HTML, including cached oneboxes, topic quotes and plugin output. Site settings cannot override that policy. Script/style/iframe/object/embed/SVG/MathML bodies, event handlers, inline styles and executable URL schemes are excluded. This deliberately loses some upstream rich rendering and requires explicit reviewed policy changes for later compatible features.

Unknown uploads become readable labels, unknown mentions/hashtags remain readable text, and missing oneboxes remain links. The cooker makes no request to discover metadata. The renderer may later load ordinary image URLs or follow user-selected links; prohibiting network inside the cooker does not mean all rendered media is cached offline.

The corpus checks common Markdown, protected code, emoji, BBCode/spoilers, post/chat rule differences, known/missing metadata, hostile raw HTML and hostile cached raw oneboxes. The same fixture file is exercised in Node and the native VM. These are pinned-engine smoke/parity checks, not a claim of complete server `PrettyText.cook` equivalence: Ruby cleanup, arbitrary Ruby plugin callbacks, chat slash commands and missing plugin counterparts remain later milestones.

## Actual validation and measurements

Measured on macOS 26.6.2 ARM64 with Flutter 3.47.4 / Dart 3.13.3. Full command outputs and benchmark HTML are retained under [evidence/milestone-1](evidence/milestone-1/README.md); large build/test outputs are gzip-compressed without truncation.

| Check actually run | Result |
| --- | --- |
| JS exact bundle regeneration and corpus | Passed; 17 Node tests |
| QuickJS vendored source verification | Passed; 21 files |
| Package `dart analyze --fatal-infos` | Passed |
| Package randomized Dart tests, seed `1187662061` | Passed; 39 tests |
| Root Flutter native-asset smoke | Passed; 1 test |
| Focused root library/new test analysis | Passed |
| Full root analysis | One existing lint: `test/content_route_test.dart:19`, `prefer_const_literals_to_create_immutables`; source unchanged from base |
| Full root tests, seed `67214` | Incomplete: 11,599 passed, 7 skipped, 288 failures before interrupting an existing hang; baseline had 11,598 passed and exactly the same 288 failures/skips/hang |
| Compatibility wrapper analysis | Passed |
| Root + compatibility iOS simulator debug app builds | Both passed; both embed `discourse_cooking.framework` |
| Root + compatibility macOS unsigned debug Xcode app builds | Both passed; both embed `discourse_cooking.framework` |
| Standalone macOS AOT build and execution | Passed using `dart build cli` |
| Native C iOS device/simulator ARM64 compilation | Passed; compile-only, no device execution |
| Linux runtime/AOT/app packaging | CI configured; not run locally |
| iOS device / Android / Windows / web execution | Not run; Android/Windows are planned application targets, web unsupported by this package |

The full root test run is **not a passing gate**. An untouched export of starting commit `836f22900bfe091bddc62b9959802641e605188a` reproduced exactly all 288 completed failure names, with no candidate-only or baseline-only failures. Both stopped progressing in `modal_controller_lifecycle_test.dart`, “user cards an open user card follows a replacement controller.” After observing the identical stopped state, both processes received SIGINT; their final summaries count the interrupted test as an additional failure (289). The new root cooking smoke accounts for the candidate's one additional pass. [Baseline comparison](evidence/milestone-1/baseline-comparison.json) lists every shared failure, and both complete pre/post-interrupt outputs are retained. This comparison establishes no regression among completed tests, not success of the incomplete suite. No unrelated UI tests/source were modified.

Native boundary tests exercise an infinite loop, regex backtracking, a thrown object's looping `toString`, allocation pressure, blocking `Atomics.wait`, embedded NUL, output caps and repeated disposal. Worker tests include timeout fallback, VM replacement after output failure, disposal during startup and with admitted queued work, bounded queue admission, main-isolate responsiveness, and all 13 shared Node/native fixture cases.

The checked-in standalone bundle is 628,169 bytes, SHA-256 `3458686854d55ea5b7d7de2adcd12d781ddb06ce3b3b25163e9414e4f2912007`.

| Final representative benchmark (100 samples after 10 warmups) | Dart JIT | Dart AOT |
| --- | ---: | ---: |
| Worker + library + bundle startup | 185.444 ms | 249.218 ms |
| Warm round-trip median | 31.312 ms | 29.332 ms |
| Warm round-trip p95 | 39.063 ms | 30.125 ms |
| Warm engine median | 30.978 ms | 29.191 ms |
| Final QuickJS allocated heap | 2,988,096 bytes | 2,988,096 bytes |
| HTML output | 495 UTF-8 bytes | 495 UTF-8 bytes |
| Whole-process RSS before / after | 228,704,256 / 226,607,104 bytes | 16,154,624 / 28,950,528 bytes |

These are one host run, not a performance guarantee or peak-memory measurement. Startup excludes compilation/dependency installation. Other Xcode/test work was active on the host; JIT RSS can fall due to GC and is not an incremental VM allocation estimate. QuickJS's own initial empty heap was 92,648 bytes; a 20 ms infinite-loop budget interrupted around 20.2 ms in the native smoke. The cooker reconstructs per-request parser/context state for isolation, accounting for much of the warm latency.

## Remaining scope

No chat/composer UI, optimistic send/edit/draft reconciliation, plugin catalog/cache integration, complete Chat parity or topic/composer consumer is implemented here. Snapshot dictionaries are intentionally an immutable JSON skeleton; later milestones should provide richer catalog/field contracts and context construction. Arbitrary Ruby plugin callbacks cannot run in this engine; supported pure transformations require explicit local counterparts.

Linux CI runs the package/native corpus and standalone AOT smoke. Existing application CI also checks macOS and iOS simulator packaging through the root dependency graph. No Android job or local Android run is claimed; a configured check is not evidence of a local successful run. Web is unsupported; it has neither Dart isolates nor this native asset. Windows is not an application-supported target and has not been validated. The C engine is a vendored security-sensitive dependency and must be deliberately updated along with provenance and corpus review.
