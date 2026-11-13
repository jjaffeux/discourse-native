# Architecture improvements, round sixteen

Baseline `0067e90d8`. The graph counts distinct application libraries reachable
through imports and exports, including the entry point. For extracted code, the
baseline is its former owning library. Widget counts use the graph's existing
classification. The measurements describe static dependencies.

| # | Change | App libraries | Widget libraries | Focused tests |
| --- | --- | --- | --- | --- |
| 1 | Do Not Disturb uses its own account API | 85 → 10 | 0 → 0 | `do_not_disturb_controller_test.dart`, `do_not_disturb_dialog_test.dart` |
| 2 | Account preferences use a dedicated preferences API | 85 → 38 | 0 → 0 | `preferences_controller_test.dart`, `user_preferences_test.dart` |
| 3 | User summaries use a dedicated read API | 85 → 37 | 0 → 0 | `user_summary_controller_test.dart`, `user_summary_test.dart` |
| 4 | Chat transcript parsing is independent of rendering | 822 → 179 | 303 → 2 | `chat_transcript_test.dart`, `cooked_markup_totality_test.dart` |
| 5 | Lazy Vimeo and TikTok parsing is independent of the embed widget | 776 → 1 | 302 → 0 | `lazy_embedded_video_test.dart` |
| 6 | Mermaid fence parsing and replacement are independent of editor widgets | 776 → 1 | 303 → 0 | `mermaid_composer_test.dart` |
| 7 | Site read policy receives six site-read operations | 84 → 40 | 0 → 0 | `site_read_policy_test.dart`, `account_feed_retention_test.dart` |
| 8 | Preview loading receives only the user card and liker operations | 88 → 47 | 0 → 0 | `preview_loading_test.dart` |
| 9 | Draft listing uses a dedicated drafts API | 87 → 41 | 0 → 0 | `draft_list_controller_test.dart` |
| 10 | Composer block controls use a block surface host | 345 → 265 | 137 → 137 | `composer_block_surface_test.dart`, `composer_block_drag_edges_test.dart`, `composer_embedded_document_test.dart`, `composer_history_toolbar_test.dart` |

The four extracted API libraries preserve the aggregate's exports and raise
plugin contract reach from 174 to 178 app libraries, with two widget libraries
in both snapshots. Shell composition reaches 537 app libraries, up from 532,
with the same 138 widget libraries. The three parser widget entry points each
reach six more app libraries, with their widget counts unchanged.

An intervening Voice URL fix had widened the Voice onebox parser from one to
175 reachable app libraries through the plugin contracts barrel. A narrow
public URL entry point keeps the same resolver and brings that parser to
three app libraries and zero widget libraries.

Run `flutter test test/architecture_round_sixteen_contract_test.dart` to verify
the new limits. Run `dart run tool/architecture_graph.dart` with the paths below
prefixed with `lib/src/` in the corresponding checkout to reproduce the counts.

| Baseline entry point | Updated entry point |
| --- | --- |
| `shell/do_not_disturb_controller.dart` | `shell/do_not_disturb_controller.dart` |
| `shell/preferences_controller.dart` | `shell/preferences_controller.dart` |
| `shell/user_summary_controller.dart` | `shell/user_summary_controller.dart` |
| `plugins/chat/chat_transcript.dart` | `plugins/chat/chat_transcript_data.dart` |
| `plugins/discourse_lazy_videos/lazy_embed.dart` | `plugins/discourse_lazy_videos/lazy_embed_parser.dart` |
| `plugins/discourse_mermaid/mermaid_composer.dart` | `plugins/discourse_mermaid/mermaid_composer_source.dart` |
| `shell/site_read_policy.dart` | `shell/site_read_policy.dart` |
| `shell/preview_requests.dart` | `shell/preview_requests.dart` |
| `shell/draft_list_controller.dart` | `shell/draft_list_controller.dart` |
| `shell/composer/block_surface.dart` | `shell/composer/block_surface.dart` |
