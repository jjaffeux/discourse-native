# Architecture improvements, round seven: one-way layers and cycles

Baseline: `4627b1dc9`. Round six left a 177-library cycle inside the shell and
two pairs of layers that depended on each other. This round removes every
cycle outside the composer and shell widgets, makes every layer one-way, and
gives three `ShellController` responsibilities their own owners.

Reproduce every row of the scorecard with
`tool/architecture_scorecard.py <base> <head>`, and the sizes with
`tool/library_kernel_cost.py`. `test/architecture_*_contract_test.dart` fail if
a number regresses.

## Results

| Measure | Baseline | Final |
| --- | --- | --- |
| Import cycles | 11 | 3 |
| Libraries in a cycle | 251 | 100 |
| Largest import cycle | 177 | 84 |
| Pairs of layers that depend on each other | 2 | 0 |
| Widget libraries `ShellController` reaches | 345 | 140 |
| Libraries `shell_controller.dart` reaches | 771 | 509 |
| Libraries `composer/controller.dart` reaches | 771 | 366 |
| Libraries `models/topic.dart` reaches | 41 | 34 |
| Libraries `plugin_api/site_plugin_api.dart` reaches | 128 | 99 |
| Mean application libraries per test file | 548 | 523 |
| Lines in `shell_controller.dart` | 10,649 | 10,177 |

Kernel size is deterministic and is what a library pulls in to compile:

| Entry | Before | After |
| --- | --- | --- |
| `models/site_config.dart` (control) | 64.8 MB | 64.8 MB |
| `models/topic.dart` | 69.5 MB | 65.3 MB (-6%) |
| `data/discourse_api.dart` | 71.3 MB | 68.5 MB (-4%) |
| `plugin_api/site_plugin_api.dart` | 78.6 MB | 67.2 MB (-15%) |
| `shell/composer/controller.dart` | 143.3 MB | 109.3 MB (-24%) |
| `shell/shell_controller.dart` | 143.3 MB | 132.9 MB (-7%) |
| `discourse_plugin_sdk.dart` | 143.4 MB | 143.5 MB (unchanged) |

Compile times are not quoted. The before and after runs had different machine
load, and the control library's time moved by 30% between them.

## Improvements and proof

Each row names a contract that fails on the old structure. The failure text
below is the disagreement each contract was written to catch.

| # | Improvement | Before | After and primary proof |
| --- | --- | --- | --- |
| 1 | Composer controllers no longer reach composer widgets. Projections keep their geometry; `ComposerArtwork` draws them, installed by `ComposerEditor`. The preference controllers left their host widget libraries. | 17 edges from the controller core into widgets. | Cycle 177 to 84. Reintroducing an edge fails `architecture_composer_widgets_contract_test.dart` with `Which: larger than expected`. `composer_artwork_test.dart` drives a recording artwork with no shell. |
| 2 | Icon vocabulary sits below models. | 12 model and 1 data edge into `theme`. | `models <-> theme` gone. Importing `theme/d_icon.dart` from a model fails with that edge named. |
| 3 | The theme sits below the kit. | 7 edges from `theme` to `ui`. | `theme <-> ui` gone. `app_theme.dart` reach 63 to 19. |
| 4 | HTTP transport and API contracts have no cycle. | 7-library cycle, with contracts importing a concrete API module. | Gone. Reintroducing it fails `Expected: empty, Actual: [[discourse_api_contracts, discourse_transport, dsa_notices_api]]`. |
| 5 | The plugin API has no cycle. | Cycles of 9 and 3. | Both gone. Exported barrel names are unchanged. `site_plugin_api.dart` reach 128 to 99. |
| 6 | Chat's data layer is one-way. | 18-library cycle joining wire models to the controller. | Gone. A model importing the controller fails with the closure named. |
| 7 | Chat views stop reaching the plugin entry. | 24-library cycle. | Gone. Views take route ids and destinations from small libraries. |
| 8 | The five leaf cycles are gone. | AI 4, kit 3 and 2, events 2, gamification 2. | All gone. |
| 9 | `UserMenuNotifications` owns counts and plugin feeds. | 283 lines in `ShellController`, and a forwarding host. | 306 lines leave, and the forwarding host is deleted. Removing the admission guard fails a shell-free test. |
| 10 | `SiteReadPolicy` decides whether a public read carries an account. | Five connected-account gates. | One gate. Restoring an `apiKey != null` gate fails `apiKey: orphaned` against `apiKey: null`. |
| 11 | `TopicFilterLookups` owns the lease checks. | Unpinned rechecks. | Removing the post-lookup recheck fails `Expected: empty`. |

## Limits

- The 84-library cycle remains: the composer panel and its editor widgets
  through `ComposerRichBodyEditor`, and the shell's page widgets through
  navigation. The 13-library cycle holds the composer controllers through
  `components/emoji.dart`. A 3-library cycle holds shell scope wiring.
- `discourse_plugin_sdk.dart` still reaches 803 libraries, so a plugin file that
  needs only a wire type recompiles with the shell.
- `ShellController` still reaches 140 widget libraries; 129 are the kit.
- Rendering a composer component with no `ComposerEditor` above it throws a
  `StateError`. Every production surface mounts one; tests that draw a bare
  controller pass `artwork: const CoreComposerArtwork()`.

## Test status

A broad related set of 405 files ran on this series before its last rebase:
27,306 tests passed and 22 failed. The same 22 fail in those files on `main` at
`4627b1dc9`, without this work.

After the last rebase, 235 chat, composer, and architecture files ran: 6,736
passed and 4 failed. All 4 are among the same 22.
