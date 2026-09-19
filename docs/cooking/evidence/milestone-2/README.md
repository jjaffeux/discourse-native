# Milestone 2 validation evidence

Validated on macOS ARM64 in the milestone worktree, 2026-09-19. Logs contain
actual command output (trailing whitespace normalized); no full-suite success or new cross-platform build is
claimed.

| Command / scope | Result | Log |
| --- | --- | --- |
| Package `dart analyze --fatal-infos` | Passed, no issues | `package-analysis.txt` |
| Package `dart test` | Passed, 56 tests | `package-tests.txt` |
| JS `npm test` | Passed, 22 tests | `js-tests.txt` |
| JS `npm run verify` | Exact generated bundle reproduction | `bundle-verification.txt` |
| `python3 packages/discourse_cooking/tool/vendor_quickjs.py` | 21 pinned source files verified | `quickjs-verification.txt` |
| Root `flutter pub get --enforce-lockfile` | Passed | `root-pub-get.txt` |
| `profiles/full` `flutter pub get --enforce-lockfile` | Passed | `full-pub-get.txt` |
| Root focused Flutter tests, seed 67214 | Passed, 149 tests | `root-focused-tests.txt` |
| Plugin dependency boundaries | 16 passed, 1 existing Assign import failure | `plugin-boundary-tests.txt` |
| Root `flutter analyze --no-pub` | Only existing `test/content_route_test.dart:19` const-literal info | `root-analysis.txt` |
| `profiles/full` `flutter analyze --no-pub` | Passed, no issues | `full-analysis.txt` |
| Changed root Dart format check | Passed, 16 files unchanged | `format.txt` |

Package commands run from `packages/discourse_cooking`; JavaScript commands run
from its `js` directory. The exact focused root test command was:

```sh
flutter test --no-pub --reporter expanded --test-randomize-ordering-seed=67214 \
  test/application_cooking_test.dart \
  test/application_cooking_worker_test.dart \
  test/site_config_cooking_test.dart test/site_config_test.dart \
  test/instance_store_test.dart test/plugin_runtime_test.dart \
  test/offline_cooking_runtime_test.dart test/core_plugin_profile_test.dart \
  test/build_profile_packaging_test.dart test/bundled_plugin_manifest_test.dart
```

The boundary run uses `flutter test --no-pub --reporter expanded
 test/plugin_dependency_boundary_test.dart`. Its only failure is the unchanged
Assign import of `../../shell/shell_scope.dart`. New cooking ownership was added
to the test's explicit directory/entrypoint mapping; no ownership rule was
weakened.

Coverage includes immutable and deterministic identities, declaration limits,
ownership and mixed-capability preservation, module ordering and gates, actual
worker syntax/token/document stages, hostile output sanitation, known hashtag
metadata, cold/default and stored setting provenance, bounded cache and inflight
coalescing, stale races, account upload leases, worker recreation/backoff,
idempotent disposal and real shell prewarm/teardown. Native fixture integration
runs with a host `HttpOverrides` trap and records zero HTTP clients.

The final generated JS is 634,308 bytes, SHA-256
`b3f161471c9608ffed3dc610808d4762e9f5a9ad4b2a99bc59a97282024c65cc`.
Bundle verification also checks copied Discourse sources against their pristine
hash manifest. QuickJS engine identity is generated from its pinned provenance.

The full root suite was not rerun: milestone 1 retained candidate/base evidence
of the same 288 completed failures and the modal-controller user-card hang.
This milestone did not modify native C code or repeat platform application
builds. Both locked app graphs and their packaging tests were checked; actual
worker execution was tested locally on macOS. Linux, iOS device, Android and
other platform execution is not newly claimed here.
