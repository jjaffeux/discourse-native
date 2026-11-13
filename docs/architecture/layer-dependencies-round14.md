# Architecture improvements, round fourteen

Baseline `1a3c3e964`. The graph counts distinct application libraries reachable
through imports and exports, including the entry point. For extracted code, the
baseline is its former owning library. Widget counts use the graph's existing
classification. The measurements describe static dependencies.

| # | Change | App libraries | Widget libraries | Focused tests |
| --- | --- | --- | --- | --- |
| 1 | Account sessions depend only on current-user lookup and key revocation | 88 → 53 / 94 → 77 | 0 → 0 / 0 → 0 | `account_session_coordinator_test.dart`, `discourse_account_api_test.dart` |
| 2 | Site transport uses a standalone category response and failure types | 92 → 76 | 0 → 0 | `discourse_site_api_test.dart` |
| 3 | Composer transport imports the search and failure contracts directly | 93 → 77 | 0 → 0 | `discourse_api_autocomplete_boundary_test.dart`, `composer_upload_rate_limit_test.dart` |
| 4 | Nested Replies services and bulk state are independent of sheet widgets | 773 → 178 / 329 → 174 | 304 → 2 / 135 → 2 | `nested_replies_services_test.dart`, `nested_replies_bulk_test.dart`, `nested_replies_integration_test.dart` |
| 5 | Policy email preferences and codec are independent of the preference UI | 327 → 172 | 134 → 2 | `user_preferences_test.dart`, `discourse_api_test.dart` |
| 6 | Voice room onebox parsing is independent of live state and rendering | 830 → 1 | 306 → 0 | `voice_room_onebox_test.dart` |
| 7 | Post mutation policy is a standalone owner | 521 → 117 | 138 → 1 | `post_mutation_outcome_test.dart`, `post_notice_accepted_refresh_test.dart`, `post_permanent_delete_test.dart` |
| 8 | Selected post moderation is a standalone owner | 521 → 119 | 138 → 1 | `topic_selected_posts_confirmation_ownership_test.dart`, `topic_actions_integration_test.dart` |
| 9 | Topic action transactions are a standalone owner | 521 → 118 | 138 → 1 | `topic_actions_integration_test.dart`, `topic_actions_menu_test.dart` |
| 10 | Draft revision previews receive snapshots and an animation | 337 → 181 | 137 → 133 | `composer_saved_draft_rollback_test.dart`, `composer_drafts_integration_test.dart` |

The existing API aggregate still exposes the category response and account
operations. Its two new dependency leaves increase plugin contract reach from
169 to 171, with the same two widget libraries. Existing budgets account for
the added leaves. The shell composition reaches 527 app libraries, up from
521, and still reaches 138 widget libraries. The Nested Replies bulk widget,
Policy preference widget, and Voice onebox widget reach 3, 3, and 7 more app
libraries respectively, with unchanged widget counts.

Run `flutter test test/architecture_round_fourteen_contract_test.dart` to verify
the new limits. Run `dart run tool/architecture_graph.dart` with the paths below
prefixed with `lib/src/` in the corresponding checkout to reproduce the counts.

| Baseline entry point | Updated entry point |
| --- | --- |
| `data/account_session_coordinator.dart` | `data/account_session_coordinator.dart` |
| `data/discourse_account_api.dart` | `data/discourse_account_api.dart` |
| `data/discourse_site_api.dart` | `data/discourse_site_api.dart` |
| `data/discourse_composer_api.dart` | `data/discourse_composer_api.dart` |
| `plugins/nested_replies/nested_replies_services.dart` | `plugins/nested_replies/nested_replies_services.dart` |
| `plugins/nested_replies/nested_replies_bulk.dart` | `plugins/nested_replies/nested_replies_bulk_controller.dart` |
| `plugins/policy/policy_preferences.dart` | `plugins/policy/policy_email_preferences.dart` |
| `plugins/voice/voice_room_onebox.dart` | `plugins/voice/voice_room_onebox_data.dart` |
| `shell/shell_controller.dart` | `shell/post_mutation_policy.dart` |
| `shell/shell_controller.dart` | `shell/selected_post_moderation.dart` |
| `shell/shell_controller.dart` | `shell/topic_action_transactions.dart` |
| `shell/composer/draft_preview.dart` | `shell/composer/draft_preview.dart` |
