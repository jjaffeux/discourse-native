# Coordinator acceptance

Reviewed implementation commit `a3ee11ec543fd9d2e281846198609b1c3bef0099` on 2026-09-19. Integrated into a clean checkout of current main `add44bf62` as merge commit `4dbf215e7`. Final main merge is performed from the repository main checkout; unrelated uncommitted UI work is preserved.

The coordinator inspected the JavaScript adapter, profile selection, missing-lookup behavior, final sanitizer, bundle/provenance tooling, contracts, tests and CI. An independent runtime review inspected the C/FFI ownership, monotonic interruption, worker queue/disposal/recovery and absence of host network/filesystem capabilities. No must-fix cooking defect remained.

## Independently executed on the integrated tree

- `npm ci --ignore-scripts`, `npm run verify`, `npm test`: passed; 17 tests, exact 628,169-byte bundle SHA-256 `3458686854d55ea5b7d7de2adcd12d781ddb06ce3b3b25163e9414e4f2912007`.
- Package `dart pub get --enforce-lockfile`, `dart test --test-randomize-ordering-seed=67214`, `dart analyze --fatal-infos`: passed; 39 tests, no analysis issues.
- `python3 tool/vendor_quickjs.py`: all 21 pinned source files verified.
- Root `flutter pub get --enforce-lockfile`: passed.
- Root `flutter test --no-pub --test-randomize-ordering-seed=67214 test/offline_cooking_runtime_test.dart test/plugin_dependency_boundary_test.dart test/build_profile_packaging_test.dart test/core_plugin_profile_test.dart`: 31 passed, one existing failure. The Assign plugin imports `../../shell/shell_scope.dart`; that exact failing test is present in the committed baseline comparison. The cooking native-asset smoke and packaging/core-only checks passed.
- Full `flutter analyze --no-pub`: one existing info at `test/content_route_test.dart:19`, `prefer_const_literals_to_create_immutables`. Source is unchanged from main/base.

The coordinator independently read the complete compressed candidate/baseline logs and extracted their failing test names: 288 in each, with empty candidate-only and baseline-only sets. Both runs stopped at the same existing user-card test and were interrupted. These runs are incomplete and failing, not a green repository-wide gate. See the author evidence for full commands, logs and counts.

## Acceptance boundaries

The author supplied successful root/compatibility macOS and iOS simulator build evidence with the cooking framework in all four artifacts, plus standalone AOT execution and benchmarks. Those builds were not redundantly repeated by the coordinator. Linux execution remains unverified locally; the installed Docker client has no running daemon, and Linux CI is configured but not claimed as run. iOS device execution is also unverified.

The accepted deliverable is the isolated runtime/compiler foundation, not application integration or complete server parity. Later milestones own profiles/plugin catalog/context caching, full Chat/local cleanup behavior, optimistic integration and post consumers. Host lifecycle must recreate the service after startup/transport/watchdog failure; ordinary individual engine failures recreate the VM internally. Forced termination may defer native finalization. These limitations are documented in the milestone report.
