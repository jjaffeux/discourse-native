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

The table policy now takes its render callback at composition and uses the
existing editor interface for insertion. Its reachable app libraries fell
from 299 to 31, and widget libraries fell from 136 to one. The composer cycle
now contains seven libraries. The focused table suite exercises insertion,
editing, focus, and source projection through the normal editor.

Code and details policies now receive their renderers from composer setup.
They use the editor interface for insertion, selection, and focus. Each
policy reaches 262 app libraries, down from 300. The composer cycle now
contains five libraries. Focused code block, details, source analysis, and
architecture tests cover the change.

List projection now takes its renderer from composer setup. Its policy
reaches 261 app libraries, compared with 301 for the library that previously
owned it. The embedded document range is a standalone value type that reaches
one app library. These changes remove the list and embedded document
controllers from the composer cycle, leaving three libraries. The focused
tests cover nested lists, task editing, embedded documents, and the cycle guard.

Core policy setup now receives an editor interface and typed artwork. The
artwork contract reaches 43 app libraries, down from 300, and core policy
setup reaches 272, down from 300. The composer controller no longer
participates in an import cycle. The cooked renderer remains the sole cycle,
with five libraries.

Quote blocks now take a body renderer from cooked HTML composition. The quote
library reaches 568 app libraries, down from 620, and 152 widget libraries,
down from 181. The cooked renderer cycle shrank from five libraries to four.
Nested quotes, quote layout, and cooked fragments passed focused tests.

Image grids now receive the cooked body renderer for non-image tiles from
composition. Their dependency reach fell from 620 to 584 app libraries and
from 181 to 156 widget libraries. The remaining cycle contains three libraries.
