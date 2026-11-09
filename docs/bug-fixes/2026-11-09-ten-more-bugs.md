# Ten more bugs proven red, then green

Each bug landed as a commit holding only a failing test, then a commit holding
only the production fix, on `afb660ec5`. The tag minimum also has a commit
between the two that gives two existing fixtures an author who can tag.
`tool/prove_bug_commits.py` checked out both commits of each bug in a scratch
worktree. Every test failed at its repro commit on the assertion below and
passed at its fix commit. All 15 checks held.

Rerun it from the repository root:

```sh
tool/prove_bug_commits.py docs/bug-fixes/2026-11-09-ten-more-bugs.manifest.json \
  --base afb660ec5 --out /tmp/proof.json
```

| # | What a user saw | Failing assertion before the fix | Cause and fix | Test |
| --- | --- | --- | --- | --- |
| 1 | After clocks went back, a month's weekday headers sat one column off. In `America/New_York`, November 2026 read Su Su Mo Tu We Th Fr. | In that zone: expected `[Su, Mo, Tu, We, Th, Fr, Sa]`, actual `[Su, Su, Mo, Tu, We, Th, Fr]`. In any zone: `Found 0 widgets with text "MON"`. | The calendar package steps each column by 24 elapsed hours, so after a 25-hour day a column's moment is 23:00 the day before. `headerColumnDay` corrects it for all three header builders. | [d_calendar_test.dart](../../test/d_calendar_test.dart) |
| 2 | Opening a single-value combobox listed only its current selection until the text was cleared by hand, as in the Preferences timezone and insert-date fields. | `Found 0 widgets with text "Next.js"`. | The selection's label left in the input was treated as a search. Filtering now starts when the reader edits the text, and the Users page's local workaround is gone. | [d_combobox_test.dart](../../test/ui/d_combobox_test.dart) |
| 3 | In a category with a tag minimum, an author the site does not let tag had no tag field and could never press Send. Staff were forced to tag. | Expected `null`, actual `Choose at least 1 tag for this category.` | The minimum applied to everyone. Core gates it on `site.can_tag_topics && !user.staff` (`frontend/discourse/app/models/composer.ts:837-847`). | [composer_required_tags_test.dart](../../test/composer_required_tags_test.dart) |
| 4 | Bold or italic across several paragraphs posted literal asterisks. | Expected `**one**\n\n**two**`, actual `**one\n\ntwo**`. | One pair of markers wrapped the whole selection, which is not emphasis across a blank line. Each non-empty line now gets its own pair, as core's `_getMultilineContents` writes them. | [composer_toolbar_test.dart](../../test/composer_toolbar_test.dart) |
| 5 | Typing `@Override` in code opened the people menu and moved focus to its search field, so the rest of the word went into the menu. | Expected `-`, actual `@sam`. | Triggers had no code check. Core has `triggerRule: !inCodeBlock` (`frontend/discourse/app/ui-kit/d-editor.gjs:703,741`). | [composer_triggers_test.dart](../../test/composer_triggers_test.dart) |
| 6 | Copy text and Quote pasted an upload's filename and size into the text, and a selection across an upload lost its bold and links. | The copied text held the line `logo.png1750×2000 1.21 KB` between its paragraphs. Selection: expected the paragraph break, actual `LookAfter bold`. | The `.meta` caption was read as prose. Core skips `.lightbox-wrapper .meta` (`frontend/discourse/app/lib/quote.js:11`). | [post_text_export_test.dart](../../test/post_text_export_test.dart) |
| 7 | Copy text and Quote dropped emoji, an emoji-only post quoted as nothing, and a selection across an emoji lost its formatting. | Expected `Nice :heart: work bold`, actual `Nice work bold`. Selection: expected `Nice :heart: work **bold**`, actual `Nice  work bold`. | Only text nodes were indexed. An emoji now indexes as its shortcode, and a selection matches around drawn artwork. | [post_text_export_test.dart](../../test/post_text_export_test.dart) |
| 8 | Creating a Live room from the app sent a null LiveKit choice. | Expected `false`, actual `<null>`. | The editor sent null for a room that did not exist yet. The test proves the request. The server failure is inferred: `livekit_enabled` is `not null` (`plugins/live/db/migrate/20260709165411_add_livekit_enabled_to_voice_rooms.rb:4`) and the web form sends `?? false` (`plugins/live/assets/javascripts/discourse/components/live-room-form.gjs:33`). | [voice_room_view_test.dart](../../test/voice_room_view_test.dart) |
| 9 | A healthy LiveKit call hung up when server presence lapsed, as during a forum deploy or network gap. | Expected `not null`, actual `<null>`. | `resuming_ids` was honored only for mesh, so the local user's absence read as removal. It now also covers the local user on LiveKit. The call still ends once the server stops naming them. | [voice_controller_test.dart](../../test/voice_controller_test.dart) |
| 10 | The composer never learned which @names were real, so a real person stayed an unlinked span in the preview. | Expected `Set:['sam']`, actual `SiteLookupException(SiteLookupFailure.unreachable)`. | The GET had no `.json` and no Accept header. Core's `check_xhr` raises for a GET that is neither (`app/controllers/application_controller.rb:770-774`). On `meta.discourse.org`, the same URL answered `text/html` without the header and `application/json` with it. | [discourse_search_api_test.dart](../../test/data/discourse_search_api_test.dart) |
