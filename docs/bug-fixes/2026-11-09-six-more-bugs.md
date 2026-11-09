# Six more bugs proven red, then green

Each bug landed as a commit holding only a failing test, then a commit holding
only the production fix, on `3a4fbb0f4`. `Discourse-Present` also has a commit
before those two that adds `ActiveUse`, because its test needs that API to
compile. `tool/prove_bug_commits.py` checked out both commits of each bug in a
scratch worktree. Every test failed at its repro commit on the assertion below
and passed at its fix commit. All 7 checks held.

The seventh bug is one the first batch introduced, and a second regression from
that batch is repaired in a test. Both were found by running the tests that
reference the code those batches changed, which the first runs had not covered.

Rerun it from the repository root:

```sh
tool/prove_bug_commits.py docs/bug-fixes/2026-11-09-six-more-bugs.manifest.json \
  --base 3a4fbb0f4 --out /tmp/proof.json
```

| # | What a user saw | Failing assertion before the fix | Cause and fix | Test |
| --- | --- | --- | --- | --- |
| 1 | An admin on an automatic group such as trust_level_1 was offered add, remove, owner and primary controls that could only be refused. | `Found 1 widget with key 'add-group-members'`, expected none. | Core refuses every member write there (`lib/guardian/group_guardian.rb:13-14`), and web hides them behind `canManageGroup && !automatic` (`frontend/discourse/app/controllers/group/index.js:50-53`). `Group.canManageMembers` is that answer. | [group_page_test.dart](../../test/group_page_test.dart) |
| 2 | A member with no right to edit a group was offered its Invite button, and could only get a refusal. | `Found 1 widget with key 'invite-group-members'`, expected none. | A group invite requires `can_edit_group?` (`lib/guardian/invite_guardian.rb:21`), and web nests the button inside the same gate (`frontend/discourse/app/templates/group/index.gjs:46,85`). | [group_page_test.dart](../../test/group_page_test.dart) |
| 3 | On a read-only forum, changing a topic's notification level said the site could not be reached. | Expected `The site is in read only mode. Interactions are disabled.`, actual `Couldn't reach the site.` | Paths with no `.json` and no Accept header got core's refusals as HTML with no errors array. Every write now asks for JSON. | [discourse_transport_contract_test.dart](../../test/discourse_transport_contract_test.dart) |
| 4 | Editing a report's dates left the select reading "Last 7 days" above dates that were not. | `Found 1 widget with text "Last 7 days"`, expected none. | The select held its own last pick. It now names the preset matching the controller's range and reads "Date range" otherwise. | [report_page_test.dart](../../test/report_page_test.dart) |
| 5 | Moving a Live call to a newer device let the older one take the call back. | Expected no further `join_livekit` request, actual one. | A `DUPLICATE_IDENTITY` disconnect ran the reconnect ladder, which rotated the newer device's session and evicted it. The call now ends locally with no leave, as web does (`plugins/live/assets/javascripts/discourse/lib/live/livekit-coordinator.js:282-288`). | [voice_controller_test.dart](../../test/voice_controller_test.dart) |
| 6 | Someone reading only in the app stayed unseen: `last_seen_at` and days visited stood still, and after 30 days core stopped publishing their `/notification` channel. | Expected `['true', 'true']`, actual `[null, null]`. | Core records a visit from an API key only on `Discourse-Present: true` (`lib/auth/default_current_user_provider.rb:395-405`; `app/models/user.rb:2017`). `ActiveUse` applies web's `userPresent()` rule (`frontend/discourse/app/lib/user-presence.js:20-41`), so the header goes out only while the app is in front and input arrived within the last minute. | [discourse_transport_contract_test.dart](../../test/discourse_transport_contract_test.dart) |
| 7 | One unanswered read during search discovery, such as `/directory-columns.json` timing out, hid chat search and every other plugin scope until a later attempt fully succeeded. | Expected `{chat}`, actual `{}`. | `c02f41e4b` let any unanswered read fail the whole discovery. Each read now fails alone, what answered is adopted, and the next surface asks again from there. | [global_search_controller_test.dart](../../test/global_search_controller_test.dart) |

`fe3d829a4` renamed the default notification level options, and four cases in
[group_profile_permissions_test.dart](../../test/group_profile_permissions_test.dart)
still tapped the old label. They now tap `Watching` and still assert that level
3 is saved.

The message bus keeps its fixed headers and does not carry `Discourse-Present`,
unlike web's poll. Ordinary reads and writes carry it, and core updates
`last_seen_at` at most once per `active_user_rate_limit_secs`, which defaults
to 60 seconds.
