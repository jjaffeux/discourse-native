# Six defects an independent review found in round nine

Two reviewers read the merged
[round nine](../architecture/layer-dependencies-round9.md) without its
conclusions. Each defect below landed as a commit holding only a failing test,
then a commit holding only the production fix, on `eed49be6e`.
`tool/prove_bug_commits.py` checked out both commits of each bug in a scratch
worktree. Every test failed at its repro commit on the assertion below and
passed at its fix commit. All 7 checks held.

Rerun it from the repository root:

```sh
tool/prove_bug_commits.py docs/bug-fixes/2026-11-09-round9-review.manifest.json \
  --base eed49be6e --out /tmp/proof.json
```

| # | What a user saw | Failing assertion before the fix | Cause and fix | Test |
| --- | --- | --- | --- | --- |
| 1 | On macOS, a topic moved to another category kept its old colour in the tab strip. | Expected the new category `Color`, actual `<null>`. The model check expected `false` and got `true`. | Round nine compared tabs with `ContentRoute ==`, which ignores colour, icon and subtitle. `ContentRoute.sameDisplayAs` now counts every field a route can draw, and `sameExceptAnchors` uses it. Navigation still asks `==`, under which a recoloured route is the same place. | `shell_rebuild_isolation_test.dart`, `forum_workspace_test.dart` |
| 2 | A deleted board said its forum could not be reached, and Voice said the same for a missing room. | Expected `{500: 'Couldn't load this board.', 404: 'Couldn't load this board.'}`, actual the unreachable sentence. | The transport files any non-200 read as unreachable with a status. `failureText` now gives the caller's fallback when the site answered, and keeps "Couldn't reach" for no answer. | `plugins/boards/boards_failure_text_test.dart` |
| 3 | A card move that timed out after sending toasted "Couldn't reach the site.", inviting a retry of a move that may have landed. | Expected one toast saying the result is unknown, found 0. | The write result carried `failureText`'s sentence for an unknown outcome. It now carries the unknown wording, and the page and editors stop choosing it themselves. | `plugins/boards/boards_failure_text_test.dart` |
| 4 | Chat's user card, a new direct message and Voice's call button each worded failures by hand. | Expected `empty`, actual the four files. | The contract read `log\(` inside `Dialog(` as reporting, missed `WriteException error => error.message`, and saw only `catch` blocks. It now catches those shapes and `onError` and `catchError` handlers, with a self-test for each. The four copies call `failureText`. | `architecture_failure_text_contract_test.dart` |
| 5 | A topic read after the App Settings dialog closed was never credited. | Expected `[(postNumber: 1, topicId: 1)]`, actual `[]`. | Nothing told the dwell that `forumActive` changed, so it stayed paused. `TopicViewportBinding` now requires `forumActiveChanges`, and the coordinator syncs on it. | `topic_view_lifecycle_test.dart` |
| 6 | A chat pane hidden in another tab dropped an unread recheck, so returning to it never marked the message read. | Expected `[(channelId: 9, messageId: 1)]`, actual `[]`. | The recheck was ignored while hidden. It now banks a full dwell, spent only after the reader is back, as web does through `onUserPresent`. | `chat_channel_view_lifecycle_test.dart` |

Fix 5 has a third commit that makes `forumActiveChanges` required, so a new
binding cannot leave the signal out.

Still open, from reading only: mobile navigation compares routes with
`ContentRoute ==` in `ForumContentScope.updateShouldNotify` and
`_persistMobileNavigation`, so a recolour alone may not reach those dependents.
Policy and post voting use "Couldn't reach the site." as their own fallback, so a
404 there still says it.
