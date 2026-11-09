# Ten bugs found by tracing user flows against upstream

Each bug landed as a commit holding only a failing test, then a commit holding
only the production fix, on `1ad84db9f`. Each claim was also read against the
upstream source named in its row. `tool/prove_bug_commits.py` checked out both
commits of each bug in a scratch worktree. Every test failed at its repro commit
on the assertion below and passed at its fix commit. All 10 proofs held.

Rerun it from the repository root:

```sh
tool/prove_bug_commits.py docs/bug-fixes/2026-11-09-ten-flow-bugs.manifest.json \
  --base 1ad84db9f --out /tmp/proof.json
```

| # | What a person saw | Failing assertion before the fix | Cause and fix | Test |
| --- | --- | --- | --- | --- |
| 1 | A group chat renamed from another device kept its old title until the channel list was next refreshed. | Expected `'Launch crew'`, actual `'Planning'`. | The handler dropped any edit event with no slug, and a direct message channel has none (`plugins/chat/app/models/chat/direct_message_channel.rb:23-25`). Web applies the rename and the empty slug together (`chat-subscriptions-manager.js:528-536`). | [chat_controller_test.dart](../../test/chat_controller_test.dart) |
| 2 | Pin was offered on direct messages on a forum with pinned messages turned off, and could only fail. | Expected `false`, actual `true`. | `can_manage_pins` never reads `chat_pinned_messages`, which is off by default (`plugins/chat/config/settings.yml`) and gates every pin endpoint (`channel_pins_controller.rb:39`). Web reads the setting first (`chat-message-interactor.js:163-168`), and now the app does too. | [chat_controller_test.dart](../../test/chat_controller_test.dart) |
| 3 | Replying to a topic with a post edit unfinished on the web filled the reply box with that whole post, and sending it posted a copy. | Expected empty, actual `'The whole first post, half revised'`. | Web keeps an edit under the topic's draft key (`controllers/topic.js:2076`). Only the draft list here knew to tell it from a reply. A reply composer now leaves it on the server for the web to resume. | [composer_drafts_integration_test.dart](../../test/composer_drafts_integration_test.dart) |
| 4 | A first post finished from a saved draft could be silenced as if typed by a bot, and every autosave shrank the recorded time. | Expected at least `42000`, actual `0`. | The saved typing and open times were parsed but never restored. Web restores both (`models/composer.ts:1670`), and core silences a first post under its typing threshold (`lib/new_post_manager.rb:49`). | [composer_drafts_integration_test.dart](../../test/composer_drafts_integration_test.dart) |
| 5 | Without unified New, Dismiss emptied the list while the forum's New count stayed at the old number until the next account refresh. | Expected `0`, actual `2`. | Those counts are the server's totals and only move when read again. The app now re-reads them once reset-new succeeds. | [dismiss_new_operation_test.dart](../../test/dismiss_new_operation_test.dart) |
| 6 | Dismiss on a New list opened with `?f=tracked` cleared every new topic on the forum, not the ones shown. | Expected `true`, actual `false`. | The client always sent `tracked: false`, so core moved `new_since` (`topics_controller.rb:1270-1275`). Web sends the list's filter (`discovery/list.js:154`). Core ignores the flag under a category or tag, so those lists dismiss the ids they show. | [dismiss_new_operation_test.dart](../../test/dismiss_new_operation_test.dart) |
| 7 | Topic and message search stopped at the first page, with no way to see the rest. | Expected `true`, actual `false`. | A full-page search reports more results as `more_full_page_results` (`lib/search/grouped_search_results.rb:119-120`), and the app read only the header search's `more_posts`. | [global_search_cancellation_test.dart](../../test/global_search_cancellation_test.dart) |
| 8 | On a forum hiding profiles from the public, a signed-out visitor was still offered the Users directory, by the sidebar, `/u` links and search. | Expected `['latest']`, actual `['latest', 'users']`. | `hide_user_profiles_from_public` was never read. Web gates the link and the route (`users-section-link.js`, `routes/users.js:42-46`), and the directory endpoint does not check it. | [discourse_instance_test.dart](../../test/discourse_instance_test.dart) |
| 9 | Top replies showed every reply in the topic. | Expected `[1, 3]`, actual `[1, 2, 3]`. | The app sent `summary=true`, which `TopicsController#show` does not read (`topics_controller.rb:96-105`). `TopicView` narrows on `filter=summary` (`lib/topic_view.rb:1151`), which web sends. | [topic_reading_wire_test.dart](../../test/topic_reading_wire_test.dart) |
| 10 | A solution someone else marked or removed did not appear or disappear for a person reading the topic until it was reopened. | Expected `true`, actual `false`. | Solved publishes `accepted_solution` and `unaccepted_solution` on `/topic/:id` (`accept_answer.rb`), and the app had no handler. The list names only the answers that remain, so held posts are compared with it and those that disagree are re-read, which also refreshes `can_unaccept_answer`. | [topic_channel_router_test.dart](../../test/topic_channel_router_test.dart) |

Two commits on top repair what combining these exposed. The feed benchmark in
`tool/`, added on main while the batch was built, gained the new `tracked`
parameter, and a test helper left unreferenced by a case outside this batch was
removed.
