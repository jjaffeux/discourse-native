# Architecture improvements, round nine: owners, narrow scopes and cheaper tests

Baseline: `8434b693f`. Eight earlier rounds took the import graph from one
721-library cycle to two small cycles. Graph work alone now moves little, so
this round asked each candidate for a number or a failing test before it was
accepted. Five read-only scouts measured nineteen candidates against a
throwaway baseline, and ten improvements landed.

Reproduce the per-commit graph with `tool/architecture_scorecard.py 8434b693f
<head>`, kernel sizes with `tool/library_kernel_cost.py`, and the red and green
proofs with:

```bash
python3 tool/prove_perf_commits.py docs/architecture/layer-dependencies-round9.manifest.json --base 8434b693f --out proof_results.json
```

The prover reverse-applies each commit's `lib/` change, expects its proof to
fail, and restores it and expects the proof to pass, twice per side. All nine
production proofs held with identical numbers in both rounds. The tenth commit
changes only test support and tooling, so its proof is the contract budget in
`test/architecture_layer_contract_test.dart`.

## Results

| Measure | Baseline | Final |
| --- | --- | --- |
| Mean application libraries per test file, following test helpers | 663 | 544 |
| Libraries compiled by `test/support/fakes.dart` | 1,087 | 225 |
| Libraries recompiled when `plugin_registry.dart`'s API changes | 581 | 340 |
| Libraries reached by `ShellController` | 515 | 502 |
| Widget libraries reached by `ShellController` | 141 | 138 |
| Elements rebuilt on macOS by a tracking message | 46 | 4 |

The baseline's 663 is a corrected figure. The old tool counted only a test's
direct imports and reported 434, because `test/` helpers were invisible to it.
Item 1 below fixed the instrument, so the scorecard's whole range uses the new
measure. The `fakes.dart` baseline was measured at `1ad84db9f`, where this work
started.

## Improvements and proof

| # | Improvement | Before | After and primary proof |
| --- | --- | --- | --- |
| 1 | `test/support/fakes.dart` stops compiling the bundled plugins, and the graph tool sees test helpers. | 655 test files reached the fake, and it compiled the plugin manifest. | Closure 1,087 to 225. 370 test files stop reaching the manifest. Restoring the old fake fails `the shared test fakes stay within their closure budget`, `Expected: <225>`, `Actual: <1087>`. |
| 2 | Desktop panels and panel tabs select the workspace rather than the whole shell. Scroll anchors are the one named field excluded. | 46 elements rebuilt, 42 of them panel frame. | 4 and 0. A tab switch, a minimized restore and a retired session still rebuild, each pinned by a test. |
| 3 | `SitePresentationScope` and `DestinationBookmarksScope` hand leaf widgets their owners. | 100 emoji images made 102 shell listeners and 1,000 URL resolutions over 10 notifications. | 2 and 0. Bookmark item rebuilds 10 to 0. `site_emoji_image` reach 520 to 55. Four paths that changed an emoji's answer without any signal now report it. |
| 4 | The topic viewport coordinator compiles without the shell. | Reach 517, kernel 133.2 MB. | Reach 41 when landed, kernel 65.9 MB. The contract fails with `not contains shell_controller.dart`. |
| 5 | The plugin runtime and scope leave the contracts barrel. | A registry API change recompiled 581 libraries. The registry changed in 96 commits since August. | 340. Contracts closure 166 to 163. Exporting either file from the barrel fails the contract. |
| 6 | The composer controllers compile without the widget kit. | Controller reach 348, widget libraries reached 139, kernel 108.8 MB. | 168, 4 and 79.2 MB. The markdown controller goes from 258 to 97 and from 106.4 MB to 77.2 MB. |
| 7 | `foundation/read_dwell.dart` is the one owner of reading dwell for chat and topics. | Two hand copies. A chat credit owed while inactive was lost, and a clock set back during a dwell stretched it. | Both credit correctly, each failing first with the expected record list. `test/read_dwell_test.dart` runs with no Flutter binding, which the private chat copy made impossible. |
| 8 | `_ForumAccessState` owns connect errors, the unreachable gate and retries. | A retired account's retry cleared its successor's gate and ended its retry. | `stale_cleared_successor` and `stale_ended_successor_retry` 1 to 0. Four shell fields and three removal lines become one record and one `forget`. |
| 9 | `_SiteCapabilities` owns composer capabilities, the post action catalog and server plugin names. | Overlapping reads made 2 requests, and capabilities survived removing the forum. | 1 read, nothing retained. A new account at the same URL gets its own read. |
| 10 | `failureText` is the one owner of a failure's user-facing sentence. | Boards showed four Dart type names, for example `WriteException(WriteFailure.validation, statusCode: 422, retryAfter: null)`. Hand copies disagreed. | 0 shown, and the server's own `Column is full` reaches the user. A contract scans catch blocks for a stringified error and names `authenticator.dart` as the exception. |

One further commit narrows the Zendesk module to the contracts barrel, which had
left `architecture_sdk_contracts_contract_test` red on main.

## Behaviour changes

Items 1 to 6 are meant to change no behaviour. The fixes in items 7 to 10 do,
and item 3 has two small timing effects, listed last:

- A failed Boards read or move shows the reason or a localized fallback. A 401 or
  403 reads "This account can't access that."
- Post voting, events and Voice now show the unreachable message where they
  showed a generic fallback.
- Assign no longer prints the raw text of an unknown error.
- A chat read credit owed while the app is inactive costs a full dwell after
  resume instead of being lost. A clock moved back during a dwell credits at once
  on return, on both surfaces.
- A retired account's retry stops asking later plugins and writes nothing.
- Server plugin names are also dropped on an account rotation at the same URL, so
  `supportsComposerColors` reads false until the new session's bootstrap lands.
- `SitePresentationController` and `AccountDestinationBookmarks` are built at the
  first `ShellScope` build rather than first use, so the five-minute freshness
  window for persisted data starts at mount.
- Emoji images rebuild on every `emojiChangesFor` firing. `EmojiImage` reloads only
  when its URL differs, so this costs a rebuild and no network.

## Limits

- The two cycles are unchanged and the scouts confirmed both refusals from round
  eight: cutting `controller -> core` needs a one-implementer interface, and
  injecting a builder into `cooked_html` leaves the recursion in the data.
- The composer change frees the controllers, not most tests. Only 18 of about
  1,600 test files stop compiling the kit, and 976 of the 990 that reach a composer
  controller still reach it through other imports.
- Compile time was measured under load, so it is secondary to the deterministic
  numbers above. `chat_search_controller_test` went from 22.8 s to 13.2 s, with
  non-overlapping ranges apart from one outlier. `update_test` went from 20.8 s to
  17.1 s with overlapping ranges, which is inconclusive.
- Full-suite time should barely move, because one `flutter test` run shares its
  incremental compiler across files. The gain is for focused runs. This is an
  inference, not a measurement.
- A test that pairs `installedPlugins` with a default fake can hang rather than
  fail when the fake answers without the plugin's value.
- Nobody looked at the running app. The desktop panel and emoji changes were
  checked by widget tests on macOS and iOS variants.
