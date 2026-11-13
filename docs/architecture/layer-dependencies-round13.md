# Architecture improvements, round thirteen

Baseline `c2591af22`. The graph counts distinct application libraries reachable
through imports and exports, including the entry point. For extracted code, the
baseline is its former owning library. Widget counts use the graph's existing
classification. The measurements describe static dependencies.

| # | Change | App libraries | Widget libraries | Focused tests |
| --- | --- | --- | --- | --- |
| 1 | DSA notices use their own request contract | 89 → 33 | 0 → 0 | `dsa_notices_api_test.dart`, `dsa_notice_controller_test.dart` |
| 2 | Search adapters use the search or failure contracts directly | 89 → 67 / 82 → 54 / 89 → 64 | 0 → 0 / 0 → 0 / 0 → 0 | `discourse_search_api_test.dart`, `global_search_controller_test.dart`, `recent_search_history_test.dart` |
| 3 | Custom sidebar state uses a three-operation API | 77 → 37 | 0 → 0 | `custom_sidebar_sections_test.dart` |
| 4 | Nested Replies reader memory is independent of the reader widget | 761 → 172 | 303 → 2 | `nested_replies_reader_test.dart`, `nested_replies_services_test.dart` |
| 5 | Post Voting category state is independent of the settings sheet | 761 → 172 | 302 → 2 | `post_voting_controls_test.dart`, `post_voting_integration_test.dart` |
| 6 | Voice call actions and teardown are independent of native and widget bindings | 842 → 171 | 316 → 2 | `voice_call_controller_port_test.dart`, `voice_call_widget_test.dart`, `voice_picture_in_picture_test.dart` |
| 7 | Current-user directory has its own library and shell callbacks | 514 → 38 | 138 → 0 | `current_user_freshness_test.dart`, `current_user_refresh_test.dart` |
| 8 | Instance rail transactions receive only the list and its effects | 514 → 31 | 138 → 0 | `instance_reordering_test.dart` |
| 9 | Topic metadata transactions receive explicit write and publication dependencies | 514 → 115 | 138 → 1 | `topic_metadata_transactions_test.dart`, `topic_title_field_ownership_test.dart` |
| 10 | Composer undo scope receives a history host | 333 → 3 | 137 → 1 | `composer_edit_history_test.dart`, `composer_history_toolbar_test.dart` |

The existing API aggregate continues exposing the same contracts. Three new
contract libraries raise the plugin contracts barrel's reach from 166 to 169,
with the same two widget libraries. Existing tests account for those three
libraries. The shell composition reaches 521 app libraries, up from 514, with
138 widget libraries in both snapshots. The Nested Replies reader and Post
Voting settings widget each reach 769 app libraries, up from 761. The Voice
binding reaches 850, compared with 842 for the previous combined port. Widget
counts for those three presentation entry points stay the same.

Run `flutter test test/architecture_round_thirteen_contract_test.dart` to verify
the new limits. Run `dart run tool/architecture_graph.dart` with the paths below
prefixed with `lib/src/` in the corresponding checkout to reproduce the counts.

| Baseline entry point | Updated entry point |
| --- | --- |
| `data/dsa_notices_api.dart` | `data/dsa_notices_api.dart` |
| `data/discourse_search_api.dart` | `data/discourse_search_api.dart` |
| `shell/global_search_api.dart` | `shell/global_search_api.dart` |
| `shell/recent_search_history.dart` | `shell/recent_search_history.dart` |
| `data/custom_sidebar_sections.dart` | `data/custom_sidebar_sections.dart` |
| `plugins/nested_replies/nested_replies_reader.dart` | `plugins/nested_replies/nested_replies_reader_memory.dart` |
| `plugins/post_voting/post_voting_category_settings.dart` | `plugins/post_voting/post_voting_category_controller.dart` |
| `plugins/voice/voice_call_controller_port.dart` | `plugins/voice/voice_call_controller_port.dart` |
| `shell/shell_controller.dart` | `shell/current_user_directory.dart` |
| `shell/shell_controller.dart` | `shell/instance_rail_transactions.dart` |
| `shell/shell_controller.dart` | `shell/topic_metadata_transactions.dart` |
| `shell/composer/history_scope.dart` | `shell/composer/history_scope.dart` |
