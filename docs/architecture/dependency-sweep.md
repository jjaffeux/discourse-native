# Repository-wide dependency sweep

The sweep starts from `28771ff42`. It uses the application import graph to
locate boundaries where independent behavior reaches a composition library,
a widget, or a wider API than it uses. The graph counts distinct application
libraries, including the entry point. Runtime behavior is checked with the
affected tests.

## API composition and editor policies

The API aggregate now composes domain contracts and preserves its existing
exports. Production callers outside the composition roots import individual
contracts. The plugin contracts entry point exports the same domain types
directly and reaches 167 app libraries, down from 181. Its paging policy is
available independently of the scrolling widget, which the full SDK supplies.

| Entry point | Reachable app libraries before → after |
| --- | ---: |
| Plugin core host | 112 → 74 |
| Topic data owner | 126 → 94 |
| Notification preferences | 97 → 63 |
| Live site sessions | 105 → 64 |
| Profile writes | 96 → 27 |
| Invite controller | 93 → 38 |
| Composer upload placeholder policy | 351 → 15 |
| Composer video policy | 351 → 29 |

Composer upload and video policies receive artwork and editor operations at
composition. The composer import cycle shrank from ten libraries to eight.
The cooked renderer still has a five-library cycle. Three bundled plugin
libraries moved off the full SDK, bringing its direct importer count to 82.

Run `dart run tool/architecture_graph.dart` for the graph, and
`flutter test test/architecture_layer_contract_test.dart test/architecture_sdk_contracts_contract_test.dart test/architecture_shell_cycles_contract_test.dart`
for the boundary checks. Shell composition reaches nine more libraries
through its split domain contracts, with unchanged widget reach.

## Remaining audit

Inspect the remaining composer cycle and the cooked renderer cycle separately.
The renderer's recursion is intentional, so a change needs evidence of a
smaller ownership boundary and equivalent nested output. Review direct plugin
SDK consumers by role, distinguishing composition and widget entry points from
libraries that only use data or lifecycle contracts. Extend the same review
to shared packages and platform adapters, which the app library graph does
not cover.
