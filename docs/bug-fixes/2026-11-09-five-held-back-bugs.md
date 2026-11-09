# Five fixes held back from the previous batch

These were proven alongside
[the ten flow bugs](2026-11-09-ten-flow-bugs.md) and held back for review. Each
is a commit holding only a failing test, then a commit holding only the
production fix, on `debd4a990`. `tool/prove_bug_commits.py` checked out both
commits of each bug in a scratch worktree. Every test failed at its repro commit
on the assertion below and passed at its fix commit. All 5 proofs held.

Rerun it from the repository root:

```sh
tool/prove_bug_commits.py docs/bug-fixes/2026-11-09-five-held-back-bugs.manifest.json \
  --base debd4a990 --out /tmp/proof.json
```

| # | What a person saw | Failing assertion before the fix | Cause and fix | Test |
| --- | --- | --- | --- | --- |
| 1 | A chat message deleted before someone opened the channel stayed missing after it was restored, until the channel was reopened. | Expected `[1, 2, 3]`, actual `[1, 3]`. | An ordinary reader is never sent a trashed message (`plugins/chat/app/queries/chat/messages_query.rb:58`), and a restore only refreshed a row already held. Web adds it (`chat-channel-subscription-manager.js:215-224`). | [chat_controller_test.dart](../../test/chat_controller_test.dart) |
| 2 | Tapping the answer already given on a public event left it selected instead of taking it back. | Expected `'DELETE'`, actual `'PUT'`. | The pressed toggle resent the same status. Web leaves the event when the same status is chosen and leaving is allowed (`discourse-post-event/status.gjs:179-187`), and the app now takes the withdrawal its actions menu already used. | [event_card_lifecycle_test.dart](../../test/event_card_lifecycle_test.dart) |
| 3 | Preferences misdescribed what happens after a bookmark reminder, for example saying the topic's owner replying when core means the bookmark's owner. | At `[0]`, `'Never'` instead of `'Keep bookmark'`. | `on_owner_reply` fires when the bookmark's owner posts (`lib/post_creator.rb:447`), and `clear_reminder` keeps the bookmark (`config/locales/client.en.yml:851`). Preferences kept its own labels, and both screens now share the bookmark editor's. | [preferences_page_test.dart](../../test/preferences_page_test.dart) |
| 4 | The linked posts switch promised notifications about replies, but it controls notifications about links to your posts. | At `[0]`, `'Notify me about replies to linked posts'` instead of web's wording. | The switch controls core's linked notification. Its title now uses web's wording (`config/locales/client.en.yml:2563`). | [preferences_page_test.dart](../../test/preferences_page_test.dart) |
| 5 | A moderator's badge kept counting review items after they opened notifications, unless they opened the forum in a browser. | Expected `'true'`, actual `null`. | Core advances `last_seen_reviewable_id` only for a non-silent, unfiltered list carrying `bump_last_seen_reviewable` (`notifications_controller.rb:46-54`), which web sends (`notifications-list.js:126`). | [discourse_account_api_test.dart](../../test/data/discourse_account_api_test.dart) |

Review changed two of these before they landed.

The first version of fix 5 sent the parameter on every unfiltered read, including
the one that reconciles after a post-voting or nested-replies visit, which would
have cleared a moderator's badge when nobody had looked at the list. That read now
says it is a background one.
[topic_reader_notification_reconcile_test.dart](../../test/topic_reader_notification_reconcile_test.dart)
guards it. With the flag removed it fails with `Expected: every element(true)`,
`Actual: [false, false, false]`.

The first version of fix 1 put every live message through a new placement check,
so a sent message could stop counting as a new message below an anchored window.
`chat_conversation_reader_test.dart` caught it. A restored message now has its own
admission, and sent messages keep theirs unchanged.
