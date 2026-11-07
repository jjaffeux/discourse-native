# Fifth batch of ten verified bug fixes

All ten regression tests failed against production code at `440be441a`:
zero passed and ten failed. The final baseline run used the final tests with
the eight changed production files temporarily restored from that commit.
The fixes were restored immediately after the baseline run.

Each test name below starts with `regression fifth:`.

| # | Reproduction | Observed before the fix | Correct result | Regression test |
| --- | --- | --- | --- | --- |
| 1 | Decode an SVG response whose declared type is `IMAGE/SVG+XML; charset=UTF-8`, with enough leading metadata to exceed the byte-sniff window. | `isSvg` is false, routing a valid SVG to a raster decoder. | `isSvg` is true. An uppercase declared raster type also retains precedence over SVG-like bytes. | [avatar_loader_test.dart](../../test/avatar_loader_test.dart), `image media types are case insensitive` |
| 2 | Search for lowercase Deseret `𐐨` in text containing its uppercase counterpart `𐐀`. | HTML remains `<p>𐐀</p>` with no highlight. | The uppercase letter is highlighted, using Unicode case matching. | [search_highlight_test.dart](../../test/search_highlight_test.dart), `search highlighting matches supplementary case pairs` |
| 3 | Open the composer link `[manual](<https://example.com/manual.pdf>)` for editing. | The URL field contains `<https://example.com/manual.pdf>`, including Markdown delimiters. | The URL is `https://example.com/manual.pdf`. Editing only the label retains the original angle-delimited destination source. | [composer_link_parser_test.dart](../../test/composer_link_parser_test.dart), `angle-delimited Markdown destinations expose usable URLs` |
| 4 | Turn proofreading on, then choose off during its change notification; read the durable preference after the queued writes settle. | The controller shows off, but the stored preference is true. | Both controller and storage retain the newest choice, false. The write is queued before listeners can make another choice. | [discourse_ai_proofreading_test.dart](../../test/discourse_ai_proofreading_test.dart), `the newest proofreading preference remains durable` |
| 5 | Pass an FTP URL on the event forum's actual host, or an HTTPS URL containing credentials, to event navigation. | The handler returns true and opens the native directory. | Both URLs return false before navigation. Ordinary HTTP and HTTPS event links remain supported. | [discourse_events_plugin_test.dart](../../test/discourse_events_plugin_test.dart), `event navigation rejects non-web and credential URLs` |
| 6 | Open the forum's `/upcoming-events/` URL. | The native event handler returns false. | It opens the `events-upcoming` directory, accepting the trailing slash. | [discourse_events_plugin_test.dart](../../test/discourse_events_plugin_test.dart), `trailing-slash event directory links open natively` |
| 7 | Parse YouTube timestamp `2562047788015216h`. | Multiplication wraps to `-9223372036854774016` seconds. | Reject the overflowing timestamp with null. A representable seconds value remains accepted. | [youtube_video_test.dart](../../test/youtube_video_test.dart), `overflowing YouTube timestamps never become negative` |
| 8 | Render a birthday member named `a𐐀` without avatar artwork. | The two-code-unit initials split the second letter, throwing `string is not well-formed UTF-16`. | The avatar displays `A𐐀`, taking complete characters. | [cakeday_widget_test.dart](../../test/plugins/cakeday/cakeday_widget_test.dart), `birthday avatar initials preserve Unicode characters` |
| 9 | Summarize 239 ASCII letters followed by `é` or a joined emoji and more text. | The summary ends in a bare `e` or part of the emoji before the ellipsis. | Keep 240 complete characters before the ellipsis. The HTML parsing budget also drops a cluster crossing its boundary instead of emitting part of it. | [chat_message_summary_test.dart](../../test/chat_message_summary_test.dart), `chat summaries never truncate part of a grapheme` |
| 10 | Summarize a cooked heading followed by table cells and a paragraph in the chat inbox. | `ResultsSam2Done` joins unrelated words. | `Results Sam 2 Done`, preserving block and cell boundaries as spaces. | [chat_message_summary_test.dart](../../test/chat_message_summary_test.dart), `inbox summaries separate headings and table cells` |

## Additional failure found during verification

The related run exposed an existing compact-layout failure in
`chat_channel_list_widget_test.dart`. It also failed with the task's production
changes removed, confirming that it was present on the original `main`.

A focused new regression in
[topic_category_path_selector_test.dart](../../test/topic_category_path_selector_test.dart),
`an empty category path fits a narrow desktop slot at double text size`,
reproduced the same `A _RenderButtonGroup overflowed by 63 pixels on the right.`
An empty category path had no flexible segment, so its label could not shrink
into a 117.5-pixel slot. The root segment now uses the Native kit's existing
`DButtonGroupExpanded`, just as a selected path's last segment already does.
Both the focused regression and the original chat layout check pass after the
fix. No new kit component or option was added.

## Verification

The repaired code passed all 501 tests across the 26 related files below.
Static analysis found no issues in the 18 changed Dart files. Formatting and
`git diff --check` also passed.

Select the ten regressions with:

```sh
flutter test --no-pub --reporter expanded \
  test/avatar_loader_test.dart \
  test/chat_message_summary_test.dart \
  test/composer_link_parser_test.dart \
  test/discourse_ai_proofreading_test.dart \
  test/discourse_events_plugin_test.dart \
  test/plugins/cakeday/cakeday_widget_test.dart \
  test/search_highlight_test.dart \
  test/youtube_video_test.dart \
  --plain-name 'regression fifth:'
```

The related run uses those eight files plus these eighteen files:

```text
test/emoji_cache_test.dart
test/site_image_repository_test.dart
test/chat_channel_list_test.dart
test/chat_channel_list_widget_test.dart
test/composer_link_dialog_test.dart
test/composer_link_nested_labels_test.dart
test/composer_inline_formatting_test.dart
test/event_directory_test.dart
test/event_card_lifecycle_test.dart
test/event_export_boundary_test.dart
test/plugins/cakeday/cakeday_identity_live_test.dart
test/plugins/cakeday/cakeday_host_test.dart
test/search_html_preparation_test.dart
test/cooked_html_search_highlight_test.dart
test/youtube_player_surface_test.dart
test/oneboxes/lazy_embedded_video_test.dart
test/topic_category_path_selector_test.dart
test/topic_list_filter_bar_test.dart
```

The full suite was not run, following `AGENTS.md`. Verification uses unit and
widget tests; no native release build or manual device check was performed.
