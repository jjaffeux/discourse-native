# Ten more verified bug fixes

All ten new regression tests failed against production code at `138afd4e3`.
Each failed on its expected output, without a setup or compilation error.
The same ten tests passed after the fixes. The related suites passed all 491
tests across 19 files. Static analysis and formatting passed for all changed
Dart files.

| # | Broken behavior | Failure observed before the fix | Correct result | Regression test |
| --- | --- | --- | --- | --- |
| 1 | An uppercase HTTP scheme sends an avatar request to the forum instead of the CDN. | Expected host `cdn.example`, actual host `forum.example`. | Keep the absolute CDN address for `HTTPS`, `Http`, and mixed-case schemes. | `absolute avatar schemes are case insensitive` in [avatar_url_test.dart](../../test/avatar_url_test.dart) |
| 2 | Forum discovery interprets an explicit unsupported scheme as a hostname. | `ftp://example.com` returned `https://ftp//example.com` instead of throwing. | Reject explicit non-HTTP schemes, while accepting `localhost:4200`. | `forum discovery rejects explicit non-HTTP schemes` in [discourse_api_test.dart](../../test/discourse_api_test.dart) |
| 3 | Homepage routing skips the URL admission applied to other links. | A credential-bearing home link returned a `ContentRoute` instead of null. | Decline credential-bearing and non-HTTP home links before selecting a native page. | `home links obey URL admission before routing` in [core_link_resolver_test.dart](../../test/core_link_resolver_test.dart) |
| 4 | GIF pagination follows a cycle of already completed cursors. | After `0`, `cursor/24`, and `cursor/48`, `canLoadMore` stayed true. | Stop at a repeated cursor, retain the results, and reset cursor history for a new search. | `GIF pagination stops when a cursor repeats` in [gif_picker_controller_test.dart](../../test/gif_picker_controller_test.dart) |
| 5 | Reply and topic previews lose emoji images from cooked posts. | Expected `Nice :heart: work`, actual `Nice work`. | Preserve emoji shortcodes, including posts containing only an emoji. | `reply previews retain cooked emoji content` in [post_plain_text_test.dart](../../test/post_plain_text_test.dart) |
| 6 | Raw post previews remove literal punctuation as though every mark were formatting. | `snake_case, C#, a*b and 2 > 1` became `snakecase, C, ab and 2 1`. | Use the existing Markdown scanner to remove recognized formatting markers and preserve literal punctuation. | `raw previews preserve literal punctuation` in [post_plain_text_test.dart](../../test/post_plain_text_test.dart) |
| 7 | Plain excerpts join adjacent table cells into different words. | Expected `Name Value alpha beta`, actual `NameValue alphabeta`. | Separate header and body cells while preserving adjacent inline text. | `table excerpts separate header and body cells` in [json_test.dart](../../test/json_test.dart) |
| 8 | A search snippet can start in the middle of a Unicode grapheme. | Expected the snippet to start with `…😀`, actual start `…�`. | Expand the cut to a grapheme boundary for emoji, combining marks, and joined emoji. | `search snippets start at a whole grapheme` in [search_highlight_test.dart](../../test/search_highlight_test.dart) |
| 9 | Top Uploads has no extension filter options because its server choices are strings. | Expected `{'jpg': 'jpg', 'png': 'png', 'pdf': 'pdf'}`, actual `{}`. | Accept string choices as well as the existing object choices. The fixture follows core's `Reports::TopUploads.report_top_uploads` response. | `Top Uploads exposes string-valued extension choices` in [report_test.dart](../../test/report_test.dart) |
| 10 | Local-date `X` formatting truncates Unix seconds toward zero before 1970. | `1969-12-31T23:59:59.500Z` formatted as `0` instead of `-1`. | Floor Unix seconds, consistent with Moment's `X` token. Millisecond formatting and positive timestamps retain their results. | `Unix seconds floor instants before the epoch` in [local_date_test.dart](../../test/plugins/local_dates/local_date_test.dart) |

Every test name above has the prefix `regression:`. This command reproduces
the focused ten-test run:

```sh
flutter test --no-pub --reporter expanded \
  test/gif_picker_controller_test.dart \
  test/post_plain_text_test.dart \
  test/json_test.dart \
  test/search_highlight_test.dart \
  test/avatar_url_test.dart \
  test/discourse_api_test.dart \
  test/plugins/local_dates/local_date_test.dart \
  test/core_link_resolver_test.dart \
  test/report_test.dart \
  --plain-name 'regression:'
```

The 491-test run used those nine files plus these directly related suites:

```text
test/gif_picker_test.dart
test/gif_picker_query_ownership_test.dart
test/gif_picker_account_rollback_test.dart
test/core_link_resolution_test.dart
test/report_page_test.dart
test/search_mockup_parity_test.dart
test/topic_progress_preview_test.dart
test/topic_progress_test.dart
test/plugins/local_dates/local_date_composer_format_test.dart
test/site_url_test.dart
```

The existing relative-link assertion in `core_link_resolver_test.dart` also
failed with the original production resolver restored. It still expected
root-site file semantics after the earlier subfolder fix. The assertion now
agrees with `site_url_test.dart` and the existing directory-resolution contract.
This test correction is separate from the ten bug fixes.

The full suite was not run, as required by `AGENTS.md`. Verification used
focused unit and widget tests. No native release build or manual device check
was performed.
