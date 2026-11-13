# Architecture improvements, round seventeen

Baseline `c825955b0`. The graph counts distinct application libraries reachable
through imports and exports, including the entry point. For extracted code, the
baseline is its former owning library. Widget counts use the graph's existing
classification. The measurements describe static dependencies.

| # | Change | App libraries | Widget libraries | Focused tests |
| --- | --- | --- | --- | --- |
| 1 | Account activity and history use a dedicated account activity API | 97 → 54 / 92 → 49 | 0 → 0 / 0 → 0 | `account_activity_controller_test.dart`, `account_history_feed_owners_test.dart` |
| 2 | Topic filters and composer identity use a dedicated lookup API | 88 → 46 / 112 → 76 | 0 → 0 / 0 → 0 | `topic_filter_lookups_test.dart`, `composer_identity_resolution_test.dart` |
| 3 | Site capabilities depend on the composer query API directly | 89 → 43 | 0 → 0 | `site_capabilities_test.dart` |
| 4 | GitHub issue, commit, and pull request parsing is independent of onebox widgets | 783 → 183 | 304 → 2 | `github_issue_test.dart`, `github_commit_test.dart`, `github_pull_request_test.dart` |
| 5 | Event submit validation is independent of authoring widgets | 786 → 184 | 303 → 2 | `event_composer_test.dart`, `event_composer_parser_test.dart` |
| 6 | Chat preferences use a narrower preference UI entry point | 784 → 344 | 303 → 136 | `preferences_page_test.dart`, `plugin_dependency_boundary_test.dart` |
| 7 | Bookmark link resolution receives one topic operation and the bookmark host contract | 108 → 49 | 1 → 0 | `bookmark_link_resolver_test.dart`, `plugin_navigation_bookmark_boundary_test.dart` |
| 8 | Flag transactions receive only the write and publication operations they use | 124 → 44 | 1 → 0 | `flag_transactions_test.dart`, `post_flag_editor_ownership_test.dart` |
| 9 | Notification feed refresh receives explicit read and publication operations | 98 → 34 | 0 → 0 | `notification_feed_refresh_owner_test.dart` |
| 10 | The composer slash menu uses a narrow editing host | 349 → 182 | 137 → 133 | `composer_slash_menu_test.dart`, `composer_panel_controls_test.dart` |

Three extracted API libraries preserve the aggregate exports and raise
plugin contract reach from 178 to 181 app libraries, with two widget
libraries in both snapshots. One fewer plugin library imports the full SDK
directly. Shell composition reaches 541 app libraries, up from 537, with
138 widget libraries in both snapshots. All three GitHub widget entry points
had the same baseline count, so the table uses the issue widget as the
representative baseline. The GitHub widget entry points and the Event composer
each reach six more app libraries, with unchanged widget counts.

Run `flutter test test/architecture_round_seventeen_contract_test.dart` to verify
the new limits. Run `dart run tool/architecture_graph.dart` with the paths below
prefixed with `lib/src/` in the corresponding checkout to reproduce the counts.

| Baseline entry point | Updated entry point |
| --- | --- |
| `shell/account_activity_controller.dart` | `shell/account_activity_controller.dart` |
| `shell/account_history_feed_owners.dart` | `shell/account_history_feed_owners.dart` |
| `shell/topic_filter_lookups.dart` | `shell/topic_filter_lookups.dart` |
| `shell/composer/composer_identity_directory.dart` | `shell/composer/composer_identity_directory.dart` |
| `shell/site_capabilities.dart` | `shell/site_capabilities.dart` |
| `plugins/discourse_github/oneboxes/issue/block.dart` | `plugins/discourse_github/oneboxes/github_onebox_data.dart` |
| `plugins/discourse_events/event_composer.dart` | `plugins/discourse_events/event_submit_preparer.dart` |
| `plugins/chat/chat_preferences.dart` | `plugins/chat/chat_preferences.dart` |
| `shell/bookmark_link_resolver.dart` | `shell/bookmark_link_resolver.dart` |
| `shell/flag_transactions.dart` | `shell/flag_transactions.dart` |
| `shell/notification_feed_refresh_owner.dart` | `shell/notification_feed_refresh_owner.dart` |
| `shell/composer/slash_menu.dart` | `shell/composer/slash_menu.dart` |
