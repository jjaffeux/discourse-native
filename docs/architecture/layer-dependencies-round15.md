# Architecture improvements, round fifteen

Baseline `124be3847`. The graph counts distinct application libraries reachable
through imports and exports, including the entry point. For extracted code, the
baseline is its former owning library. Widget counts use the graph's existing
classification. The measurements describe static dependencies.

| # | Change | App libraries | Widget libraries | Focused tests |
| --- | --- | --- | --- | --- |
| 1 | Topic read receipts depend on a dedicated read contract | 83 → 42 / 94 → 77 | 0 → 0 / 0 → 0 | `topic_read_controller_test.dart`, `topic_read_receipts_transport_test.dart` |
| 2 | Topic feeds and new-topic dismissals use a dedicated feed contract | 87 → 50 / 92 → 53 | 0 → 0 / 0 → 0 | `topic_feed_controller_test.dart`, `account_new_topic_dismissals_test.dart` |
| 3 | Bookmark transactions depend on their write API and bookmark host contracts | 100 → 47 | 1 → 0 | `bookmark_transactions_test.dart`, `bookmark_write_read_budget_test.dart` |
| 4 | The Chat–Voice contract exposes service identities and room data independently of widgets | 375 → 188 / 332 → 178 / 391 → 204 | 136 → 2 / 135 → 2 / 137 → 3 | `plugin_dependency_boundary_test.dart`, `chat_inbox_room_row_test.dart`, `voice_controller_test.dart` |
| 5 | Event onebox data and parsing are independent of the widget | 784 → 176 | 306 → 2 | `event_onebox_test.dart`, `site_image_test.dart` |
| 6 | The AI related-topics codec is independent of the summary UI | 781 → 176 | 303 → 2 | `topic_model_projection_test.dart`, `topic_recommendations_tab_store_test.dart`, `discourse_ai_summary_test.dart` |
| 7 | DSA notice verification imports its own connection and failure contracts | 79 → 6 | 0 → 0 | `dsa_notice_controller_test.dart`, `dsa_notice_form_test.dart` |
| 8 | Group write delivery classification imports the write failure types directly | 80 → 39 | 0 → 0 | `groups_controller_test.dart` |
| 9 | Checklist transactions receive one mutation callback and a narrow topic-data port | 117 → 47 / 78 → 41 | 1 → 0 / 0 → 0 | `checklist_transactions_test.dart` |
| 10 | The composer selection palette receives a formatting interface | 339 → 203 | 137 → 133 | `composer_selection_menu_test.dart`, `composer_panel_controls_test.dart`, `composer_selection_toolbar_accessibility_test.dart` |

The API aggregate still exposes the original topic and bookmark contracts.
The three new contract libraries raise the plugin contracts barrel from 171
to 174 reachable app libraries, with two widget libraries in both snapshots.
The shell composition reaches 532 app libraries, up from 527, and still
reaches 138 widget libraries. The Event onebox and AI summary widgets each
reach six more app libraries, and the Chat mobile sidebar reaches seven more.
The Voice plugin reaches 25 fewer. All four retain their widget counts.

Run `flutter test test/architecture_round_fifteen_contract_test.dart` to verify
the new limits. Run `dart run tool/architecture_graph.dart` with the paths below
prefixed with `lib/src/` in the corresponding checkout to reproduce the counts.

| Baseline entry point | Updated entry point |
| --- | --- |
| `shell/topic_read_controller.dart` | `shell/topic_read_controller.dart` |
| `data/discourse_topic_api.dart` | `data/discourse_topic_api.dart` |
| `shell/topic_feed_controller.dart` | `shell/topic_feed_controller.dart` |
| `shell/account_new_topic_dismissals.dart` | `shell/account_new_topic_dismissals.dart` |
| `shell/bookmark_transactions.dart` | `shell/bookmark_transactions.dart` |
| `plugins/chat/chat_contract.dart` | `plugins/chat/chat_contract.dart` |
| `plugins/chat/chat_inbox_rooms.dart` | `plugins/chat/chat_inbox_rooms.dart` |
| `plugins/voice/voice_controller.dart` | `plugins/voice/voice_controller.dart` |
| `plugins/discourse_events/event_onebox.dart` | `plugins/discourse_events/event_onebox_data.dart` |
| `plugins/discourse_ai/ai_summary_plugin.dart` | `plugins/discourse_ai/ai_related_topics.dart` |
| `shell/dsa_notice_controller.dart` | `shell/dsa_notice_controller.dart` |
| `shell/group_write.dart` | `shell/group_write.dart` |
| `shell/checklist_transactions.dart` | `shell/checklist_transactions.dart` |
| `shell/post_checklist_write.dart` | `shell/post_checklist_write.dart` |
| `shell/composer/selection_colors.dart` | `shell/composer/selection_colors.dart` |
