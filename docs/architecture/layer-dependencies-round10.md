# Architecture improvements, round ten

Baseline `b135e2777`. Each row counts distinct app libraries reachable from the
named entry point, including the entry point itself. The graph follows imports
and exports and folds parts into their owning library. Widget counts use the
graph’s widget classification. These are dependency counts.

| # | Entry point | Change | App libraries | Widget libraries | Behavior checks |
| --- | --- | --- | ---: | ---: | --- |
| 1 | Groups route port | Moved the immutable page snapshot to the existing page types library. | 334 → 83 | 145 → 0 | `group_pages_boundary_test.dart`, `group_pages_host_test.dart` |
| 2 | Gamification models | Moved the calendar date value out of the widget implementation. The kit still exports the same type. | 319 → 165 | 134 → 2 | `gamification_models_test.dart`, `d_calendar_test.dart` |
| 3 | Poll markup parser | Moved editor projection and selection into a binding that imports only the Markdown controller surface. | 743 → 165 | 302 → 2 | `poll_composer_test.dart`, `poll_composer_pill_test.dart`, `poll_composer_panel_test.dart` |
| 4 | Local date markup parser | Moved editor projection and selection into its own binding. The parser uses the shared Markdown scanner. | 744 → 166 | 302 → 2 | `local_date_composer_parser_test.dart`, `local_date_composer_test.dart` |
| 5 | Chat stream projection | Shared elapsed-day calculation through foundation. The notice remains a presentation concern. | 750 → 172 | 302 → 2 | `chat_stream_test.dart`, `time_gap_test.dart` |
| 6 | Chat composer target | Exported the existing target types from the contracts barrel. Target identity is available without the editor. | 743 → 165 | 302 → 2 | `chat_composer_test.dart` |
| 7 | Boards controller | Injected the topic-opening operation. The page reads its availability through a boolean. | 745 → 167 | 302 → 2 | `boards_controller_test.dart`, `boards_widget_test.dart` |
| 8 | Chat shell service | Injected the topic-opening operation. The chat module still supplies the editor host to the composer widget. | 790 → 212 | 302 → 2 | `chat_shell_service_test.dart`, `chat_composer_test.dart` |
| 9 | Topic list cursor | Declared the cursor’s tab contract and implemented it in the shell tab adapter. | 503 → 87 | 138 → 0 | `topic_list_cursor_coordinator_test.dart` |
| 10 | Chat body staging | Exposed reader timing signals through a narrow plugin entry point. | 743 → 3 | 303 → 2 | `chat_message_body_staging_test.dart` |

The rounded mean application reach per test file fell from 546 to 543.
The two import cycles still contain 10 and 5 libraries. The plugin contracts
barrel gained one library, the calendar date value, and reaches 164 libraries.
Seven bundled plugin libraries stopped importing the full SDK directly.

Run the same command in the baseline and updated checkouts to reproduce the
library counts. `test/architecture_round_ten_contract_test.dart` enforces the
updated library and widget budgets for each entry point.

```sh
dart run tool/architecture_graph.dart \
  lib/src/shell/group_pages_port.dart \
  lib/src/plugins/gamification/gamification_models.dart \
  lib/src/plugins/poll/poll_composer_parser.dart \
  lib/src/plugins/local_dates/local_date_composer_parser.dart \
  lib/src/plugins/chat/chat_stream.dart \
  lib/src/plugins/chat/chat_composer_target.dart \
  lib/src/plugins/boards/boards_controller.dart \
  lib/src/plugins/chat/chat_shell_service.dart \
  lib/src/shell/topic_list_cursor_coordinator.dart \
  lib/src/plugins/chat/chat_message_body_staging.dart
```
