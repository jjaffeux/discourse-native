# Ten architecture improvements, round six: layer dependencies

Baseline: `ecafcb48a`. The five earlier rounds hardened async ownership and
retirement. This round fixes the direction of the import graph, which those
rounds did not touch.

At the baseline, 721 of 1,318 libraries formed one import cycle. Importing a
single model such as `models/topic.dart` compiled 1,035 application libraries.

## Results

Reproduce the graph numbers with `dart run tool/architecture_graph.dart`.
`test/architecture_layer_contract_test.dart` fails if any of them regress.

| Measure | Baseline | Final |
| --- | --- | --- |
| Largest import cycle | 721 libraries | 177 libraries |
| Pairs of layers that depend on each other | 8 | 2 |
| Libraries reached by `models/topic.dart` | 1,035 | 41 |
| Libraries reached by `lib/discourse_ui.dart` | 1,035 | 168 |
| Libraries reached by `data/discourse_api.dart` | 1,035 | 100 |
| Libraries reached by `plugin_api/site_plugin_api.dart` | 1,035 | 128 |
| Mean application libraries compiled per test file | 1,035 | 703 |
| Test files that compile under 200 libraries | 132 of 1,537 | 514 of 1,542 |
| Upward edges into `data` or `plugin_api` from `models` | 19 | 0 |
| Edges from `data` to `plugin_api` | 26 | 0 |
| Edges from `plugin_api` to `shell` | 8 | 0 |

Compiling one library to kernel, with Flutter alone at 52 MB for comparison:

| Entry point | Kernel size | CPU time | Wall time |
| --- | --- | --- | --- |
| `models/topic.dart` | 158 MB to 68 MB | 13.99 s to 5.16 s (-63%) | 10.13 s to 3.75 s (-63%) |
| `lib/discourse_ui.dart` | 158 MB to 82 MB | 14.74 s to 6.28 s (-57%) | 12.35 s to 5.12 s (-59%) |
| `plugin_api/site_plugin_api.dart` | 158 MB to 77 MB | 14.95 s to 5.77 s (-61%) | 12.18 s to 4.24 s (-65%) |
| `models/site_config.dart` (control) | 63 MB to 63 MB | 4.70 s to 4.62 s (-2%) | 3.52 s to 3.46 s (-2%) |

Times are medians of six runs that alternate baseline and final, in alternating
order, on a machine with other load. They were taken just before the final
rebase onto `main`. The control library did not change, so its 2% is the noise
floor. Kernel size is deterministic.

## Improvements and proof

| # | Improvement | Before | After and primary proof |
| --- | --- | --- | --- |
| 1 | The layer contract and graph report exist. | Boundary tests protected single owners from `ShellController`. Nothing stated layer direction. | Every upward edge is named and the largest cycle has a budget. Controls seed an upward edge, a part, a barrel cycle, and a widget, and each is detected. |
| 2 | `theme/` sits below the kit barrel. | `app_theme` and `d_icon` imported `discourse_ui.dart` for seven symbols, so colours and icons reached the app. | Cycle 721 to 516. `models/topic.dart` reach 1,035 to 41. |
| 3 | The kit barrel exports no shell widget. | The barrel exported six shell libraries, and `DAnimatedEmoji` imported the shell. | Cycle 516 to 345. Barrel reach 1,034 to 168. `ui` cannot reach `data`, `plugin_api`, or `shell`. |
| 4 | The styleguide is composed at the entry points. | `InstanceRail` imported the styleguide, which imports bundled plugins. | Cycle 345 to 196. `shell` cannot reach `styleguide` or `plugins`. `component_styleguide_scope_test.dart` proves the rail still offers and opens it. |
| 5 | Models are free of the kit and the transport. | Six edges to `data` and one to the kit barrel. | Both edge counts are 0. The `data` and `models` mutual dependency is gone. |
| 6 | Shared wire vocabulary sits below the plugin API. | 13 model edges to `plugin_api`, which imports 67 model libraries. | Edge count 0, and `models` cannot reach `plugin_api` transitively. |
| 7 | The data layer is free of the plugin API. | 26 edges. `ApplicationCooking` took all of `InstalledPlugins` to read one list. | Edge count 0, and `ApplicationCooking` receives its cooking plugins. Cycle 196 to 194. |
| 8 | The plugin API is free of the shell. | Eight edges, for vocabulary and for `PluginComposerHost`. | Edge count 0. `site_plugin_api.dart` reach 763 to 128. Cycle 194 to 178. |
| 9 | `ShellController` stops importing widget libraries for pure logic. | Three widget imports, two of which import it back. | One leaf `InheritedWidget` remains, pinned by the contract. Quote parsing and hashtag presentation are independent of widgets. Cycle 178 to 177. |
| 10 | Composer identity resolution has its own owner. | `ShellController` held the caches, leases, and search closures. | `ComposerIdentityDirectory` takes narrow capabilities. `shell_controller.dart` loses 169 lines, and one import replaces eight. A shell-free test fails with `Expected: null, Actual: <Instance of 'FoundHashtag'>` when the lease check is removed. |

Each commit lowers the budget in the contract test, so the commit series shows
one measured change at a time.

## Public surface

`discourse_plugin_sdk.dart` lost no exported names and gained `CategoryIcon` and
`DAnimatedEmoji`. `discourse_core.dart` did not change. `discourse_ui.dart` lost
exactly the nine names that belong to the shell: `CategoryIcon`,
`DAnimatedEmoji`, `EmojiImage`, `EmojiPickerAnchor`, `showEmojiPicker`,
`TopicCategoryPathSelector`, `TopicCategorySelector`, `TopicTagSelector`, and
`noSubcategoriesIcon`.

`PostAction.leading` became the extension `PostActionLeading`, which the SDK
exports, so a plugin keeps the same call.

## Limits

- The 177-library cycle remains, and all of it is inside `shell`. The strongest
  remaining edge is `shell_scope.dart` importing `shell_controller.dart`, and
  more than 100 libraries import `shell_scope.dart`.
- Shell-level compile time did not improve. `shell_controller.dart` compiles in
  about the same time, and its kernel falls from 158 MB to 141 MB.
- Two mutual layer pairs remain: `models` with `theme`, and `theme` with `ui`.
  Models use icon definitions and the theme uses kit tokens, so `data` and
  `models` still reach three `ui/foundation` token libraries.
- `tool/native_ui_ownership.dart` now allows `theme/` to import kit internals.
  Importing the barrel from `theme/` is what created the largest part of the
  cycle. A test pins this exception to imports from `theme/`.
- `ComposerIdentityDirectory` flips its disposed flag at its own dispose step,
  slightly before `ShellController` sets `isDisposed`. Retirement can only
  happen earlier.
- A desktop entry point that omits the styleguide opener does not compile,
  because `AppBootstrap.production` requires it.

## Verify

```sh
dart run tool/architecture_graph.dart
flutter test --no-pub \
  test/architecture_layer_contract_test.dart \
  test/plugin_dependency_boundary_test.dart \
  test/native_ui_ownership_test.dart \
  test/component_styleguide_scope_test.dart \
  test/composer_identity_resolution_test.dart \
  test/shell_credential_read_races_test.dart \
  test/standalone_owner_dependency_boundary_test.dart
```

The 207 test files this branch changed ran on the final tree: 7,322 passed and
5 failed. The same 5 tests fail on `main` at `b1f166194` without this branch,
as does one `empty_catches` analyzer finding in `byte_cache_store.dart`. The
full suite stays with CI, per `AGENTS.md`.
