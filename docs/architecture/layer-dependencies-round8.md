# Architecture improvements, round eight: the shell cycle and shared policy

Baseline: `d83a79480`. Round seven left three import cycles and a plugin SDK that
compiled the whole shell for a wire type. This round removes almost all of the
remaining cycles, gives plugins a narrow contracts barrel, extracts three more
`ShellController` owners, and gives three drifted policies one owner each.

Reproduce every row with `tool/architecture_scorecard.py d83a79480 <head>`, and
sizes with `tool/library_kernel_cost.py`.

## Results

| Measure | Baseline | Final |
| --- | --- | --- |
| Import cycles | 3 | 2 |
| Libraries in a cycle | 100 | 15 |
| Largest import cycle | 84 | 10 |
| Mean application libraries per test file | 523 | 430 |
| Plugin libraries that reach `ShellController` | 391 of 406 | 152 of 406 |
| Libraries recompiled when `shell_controller.dart`'s API changes | 573 | 330 |

Kernel size for a plugin library that only needs wire types:

| Entry | Before | After |
| --- | --- | --- |
| `plugins/prometheus_alert_receiver/alert_data.dart` | 143.6 MB | 80.4 MB (-44%) |
| `discourse_plugin_contracts.dart` (new barrel) | n/a | 80.4 MB |
| `discourse_plugin_sdk.dart` | 143.6 MB | 140.6 MB (-2%) |
| `models/site_config.dart` (control) | 64.8 MB | 64.8 MB |

## Improvements and proof

| # | Improvement | Before | After and primary proof |
| --- | --- | --- | --- |
| 1 | Links and shell chrome stop compiling the app above them. `UserCardOpenerScope` hands the card to anything that names a user. | 84-library cycle. | Cycle 84 to 13. `open_link` importing `user_card` fails with both libraries named. `user_card_opener_app_mount_test.dart` fails `Expected: not null, Actual: <null>` if the application stops mounting the scope. |
| 2 | The markdown controller compiles without the composer. | 13-library cycle. | Cycle 13 to 10, and `markdown_editing_controller.dart` no longer reaches `controller.dart`. |
| 3 | Account hosts stop importing the shell scope. | 3-library cycle, and both hosts rebuilt on every shell notification. | Gone. Hosts take the account as an input and rebuild only when it changes. Elements rebuilt by a tracking message on the macOS bookmarks tab fall from 96 to 90. |
| 4 | Plugin wire libraries stop compiling the shell. `discourse_plugin_contracts.dart` holds what 258 plugin libraries need. | Every plugin library reached the shell through the SDK. | Plugin libraries reaching `ShellController` 391 to 152. Exported names of every existing barrel are unchanged. Exporting a shell library from the barrel fails the contract. |
| 5 | Scroll-driven paging has one admission policy. | 22 hand-written copies; a failed page re-sent on every scroll update in chat, assigned lists, group members, and post voting. | One failed page is asked for once per gesture and a new drag retries it. Requests per drag fall from chat 22 to 1, assigned 20 to 1, group 10 to 1. The contract holds an exact count of call sites. |
| 6 | "Has this window elapsed" has one owner. | 12 sites read a backward clock as a young entry. | `elapsedSince` returns "older than any window". 13 table rows fail with `its start now lies ahead` without it. Comparisons that mishandle a backward clock go from 12 to 0. |
| 7 | The wait after a rate-limited write has one owner. | Four `retryAfter ?? 1s` copies disagreed with the 15s origin cooldown; five labels truncated. | Chat, voice and the composer unlock when the origin admits again. Copies 4 to 0, truncating labels 5 to 0. A sub-second wait reads `1s`. A voice join ends on retirement rather than sitting for an hour. |
| 8 | `TopicChannelRouter` owns live topic message handling. | About 130 lines in `ShellController`. | Removing a mid-callback lease recheck fails `Expected: empty, Actual: [7]`. |
| 9 | `AccountDestinationBookmarks` owns local bookmarks. | A facade notification for each toggle. | Bookmarks stop notifying the shell. Removing the queued write's account check fails `Expected: ['Preferences']`, `Actual: ['Support', 'Preferences']`. |
| 10 | `ComposerUploads` owns upload admission. `WriteCredential` replaces three copies. | About 111 lines in `ShellController`. | Removing the recheck after the credential read fails with the wrong error. Size limits read from the opened config. |

Round seven merged eleven improvements, one more than its ten. With these ten
the two rounds land twenty-one.

## Behaviour changes

Only the policy owners change behaviour, and only where a copy had drifted:

- A failed page in chat, assigned lists, or group members is asked for once per
  scroll gesture rather than on every scroll update. A new drag still retries.
- A wall clock set backward now expires a window rather than holding it shut.
- An unhinted 429 that pauses the origin holds chat, voice, and the composer for
  the origin's 15s cooldown rather than 1s or nothing. A refusal that pauses
  nothing holds the composer for 1s. An upload keeps its default cooldown.
- A wait under a second reads as `1s`, not `0s`.
- A voice join over 60s reports the refusal at once, and any shorter wait ends
  when the call is retired.

## Limits

- Two cycles remain. The 10-library cycle is the composer controller and its
  core syntax policies. Cutting `controller -> core` would need a base class
  that exists only to satisfy the metric. The 5-library cycle is cooked HTML's
  recursive grammar: quotes and oneboxes contain cooked HTML.
- 94 plugin libraries remain on the full SDK, and test files still import it.
- `ShellController` still reaches 139 widget libraries, nearly all of them the
  kit.
- User-facing behaviour of the composer and user cards was verified by widget
  and integration tests. Nobody looked at the running app on a device.
