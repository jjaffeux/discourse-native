# Architecture improvements, round twelve

Baseline `9e9dd4667`. The graph counts distinct application libraries reachable
through imports and exports, including the entry point. The baseline for
extracted code uses the library that previously owned it. Widget counts use
the graph's widget classification. These are static dependency measurements.

| # | Change | App libraries | Widget libraries | Focused tests |
| --- | --- | --- | --- | --- |
| 1 | HTTP transport and its plugin adapter import the failure types they handle | 88 → 31 / 89 → 33 | 0 → 0 each | `discourse_transport_contract_test.dart`, `discourse_transport_redirect_test.dart`, `plugin_query_transport_test.dart`, `plugin_text_transport_test.dart` |
| 2 | MessageBus bootstrap receives a current-user decoder | 45 → 37 | 0 → 0 | `site_message_bus_bootstrap_test.dart`, `message_bus_bootstrap_api_test.dart` |
| 3 | Instance storage uses an instance codec and the plugin data decoder | 55 → 42 | 0 → 0 | `instance_store_test.dart`, `app_runtime_test.dart`, `app_bootstrap_test.dart` |
| 4 | Chat draft synchronization depends on a draft editor interface | 789 → 205 | 302 → 2 | `chat_composer_draft_session_test.dart`, `chat_composer_test.dart` |
| 5 | Nested Replies admin state is independent of its settings and activity widgets | 755 → 169 | 303 → 2 | `nested_replies_admin_test.dart`, `nested_replies_services_test.dart`, `nested_replies_integration_test.dart` |
| 6 | The GIF picker session receives a presenter from its plugin module | 760 → 171 | 303 → 2 | `gif_picker_test.dart`, `gif_picker_account_rollback_test.dart`, `gif_composer_panel_test.dart` |
| 7 | Header preferences import the tuning values independently of the UI kit | 180 → 7 | 132 → 0 | `header_preferences_test.dart`, `header_motion_test.dart`, `header_motion_visual_test.dart` |
| 8 | Message archive transactions are a standalone library | 510 → 117 | 138 → 1 | `message_archive_account_transition_test.dart`, `message_archive_controller_test.dart` |
| 9 | Topic navigation attempts receive a narrow tab interface | 510 → 111 | 138 → 1 | `shell_topic_jump_navigation_test.dart`, `topic_progress_lifecycle_test.dart` |
| 10 | Slash-command detection imports the Markdown scanner directly | 331 → 5 | 137 → 0 | `composer_slash_menu_test.dart` |

The shell still composes the extracted owners. Its closure increased from
510 to 514 libraries, with 138 widget libraries in both snapshots. The Nested
Replies widget entry point still composes its controllers and reaches 761
libraries compared with 755 at baseline, with 303 widget libraries in both.
The plugin contracts barrel still reaches 166 libraries. One fewer plugin
library imports the full SDK directly.

Run `flutter test test/architecture_round_twelve_contract_test.dart` to check the
new budgets. Run the graph command against each checkout to reproduce both
counts. Paths below are relative to `lib/src/`.

| # | Baseline entry point | Updated entry point |
| --- | --- | --- |
| 1 | `data/discourse_transport.dart`, `data/discourse_plugin_transport.dart` | Same |
| 2 | `data/site_message_bus_bootstrap.dart` | Same |
| 3 | `data/instance_store.dart` | Same |
| 4 | `plugins/chat/chat_composer_draft_session.dart` | Same |
| 5 | `plugins/nested_replies/nested_replies_admin.dart` | `plugins/nested_replies/nested_replies_admin_controller.dart` |
| 6 | `plugins/gifs/gif_picker_session_impl.dart` | Same |
| 7 | `shell/header_preferences_controller.dart` | Same |
| 8 | `shell/shell_controller.dart` | `shell/message_archive_transactions.dart` |
| 9 | `shell/shell_controller.dart` | `shell/topic_navigation_attempts.dart` |
| 10 | `shell/composer/slash_menu.dart` | `shell/composer/slash_query.dart` |

For example, from the updated checkout run
`dart run tool/architecture_graph.dart lib/src/shell/composer/slash_query.dart`.
Use the updated graph script with the baseline checkout as its working directory
to include the widget counts for the baseline.
