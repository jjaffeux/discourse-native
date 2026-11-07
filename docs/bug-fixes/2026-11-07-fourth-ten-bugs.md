# Fourth batch of ten verified bug fixes

All ten new regression tests failed against production code at `6a7385048`:
zero passed and ten failed. The final baseline run used the final test files
and temporarily restored only the eight changed production files from that
commit. The fixes were restored immediately after the run.

Every regression name below starts with `regression fourth:`.

| # | Reproduction | Observed before the fix | Correct result | Regression test |
| --- | --- | --- | --- | --- |
| 1 | Preview raw text containing `Use [name] and ` followed by an inline code span containing `[u]literal[/u]`. | `Use and literal.` loses both the bracketed word and literal code syntax. | `Use [name] and [u]literal[/u].` Known formatting wrappers outside code still disappear. | [post_plain_text_test.dart](../../test/post_plain_text_test.dart), `raw previews retain literal bracketed prose and code` |
| 2 | Preview a cooked heading followed by a table and paragraph. | `ResultsNameCountSam2Done` joins unrelated words. | `Results Name Count Sam 2 Done`. Block boundaries contribute spaces. | [post_plain_text_test.dart](../../test/post_plain_text_test.dart), `cooked headings and table cells stay separate` |
| 3 | Parse `See {[https://example.com/path]}.` in the composer. | The link destination and source include an extra `]`. | Both end at `/path`. Balanced URL brackets and parentheses remain intact. | [composer_link_parser_test.dart](../../test/composer_link_parser_test.dart), `nested closing punctuation stays outside pasted URLs` |
| 4 | Enter the two supplementary Unicode letters `𐐀𐐁` into a two-slot OTP field. | Slot rendering throws `string is not well-formed UTF-16`, and the complete letters are absent. | Each slot shows one complete character and completion receives `𐐀𐐁`. Filtering, slot projection, pointer offsets and completion use character boundaries. | [d_input_otp_test.dart](../../test/d_input_otp_test.dart), `OTP slots show complete Unicode characters` |
| 5 | Insert an invalid `x` after the first digit of `1234` in a digits-only OTP field. | Filtering removes `x` but moves the caret to offset 4. | Text remains `1234`, with the caret at offset 1 where the edit occurred. An externally assigned value with no selection still gets an end caret. | [d_input_otp_test.dart](../../test/d_input_otp_test.dart), `filtering OTP input preserves the edit position` |
| 6 | Replace recipient query `old` with `new` during the query-change notification. | Both `new` and obsolete `old` are dispatched after debounce. | Only `new` is dispatched. A superseded operation cannot install its timer after its replacement. | [composer_recipient_lookup_test.dart](../../test/composer_recipient_lookup_test.dart), `a replacement query from a listener cancels the old lookup` |
| 7 | Resolve user-card artwork `uploads/card.png` on `https://example.com/community`. | The URL becomes `https://example.com/uploads/card.png`. | The URL retains `/community/uploads/card.png`, treating the forum base as a directory. | [user_card_test.dart](../../test/user_card_test.dart), `relative user card artwork retains the forum subfolder` |
| 8 | Search for `10:30`, alongside ordinary category, excluded-tag and username filters. | No searchable words remain; the clock time is never highlighted. | `10:30` remains searchable and is highlighted in the result. Actual filter operators stay excluded. | [search_highlight_test.dart](../../test/search_highlight_test.dart), `clock times are searchable text rather than filters` |
| 9 | Enter 300 supplementary Unicode letters in the flag message field, which accepts 500 characters. | Submit is disabled because the counter counts 600 UTF-16 code units. | Submit is enabled and the counter reads `200 remaining`. Validation and the counter use the same character unit as the text field's limit. | [post_flag_editor_test.dart](../../test/post_flag_editor_test.dart), `flag messages count Unicode characters at the maximum` |
| 10 | Put `:smile:` between two escaped backticks in presentation text. | The shortcode matcher returns no match, treating the escaped delimiters as code. | `smile` is matched. Genuine code spans still suppress their contents, and a backslash inside code does not escape its closing delimiter. | [site_emoji_text_test.dart](../../test/site_emoji_text_test.dart), `escaped backticks do not hide emoji shortcodes` |

The older URL punctuation assertion explicitly expected the stray bracket;
it now expects the complete unmatched suffix to be removed. The existing
malformed-bracket stress test remains intact. Preview formatting masks bracket
positions after its own link handling, preserving offsets and avoiding a
second link scan. No UI controls or public component options were added.

## Verification

The repaired code passed all 375 tests across the 22 related files below.
Static analysis found no issues in the 16 changed Dart files. Formatting and
`git diff --check` also passed.

The ten failure proofs can be selected with this command:

```sh
flutter test --no-pub --reporter expanded \
  test/post_plain_text_test.dart \
  test/composer_link_parser_test.dart \
  test/d_input_otp_test.dart \
  test/composer_recipient_lookup_test.dart \
  test/user_card_test.dart \
  test/search_highlight_test.dart \
  test/post_flag_editor_test.dart \
  test/site_emoji_text_test.dart \
  --plain-name 'regression fourth:'
```

The related verification run uses those eight files and these fourteen files:

```text
test/composer_link_dialog_test.dart
test/composer_link_nested_labels_test.dart
test/styleguide/input_otp_examples_test.dart
test/composer_recipients_search_test.dart
test/user_card_popover_test.dart
test/user_card_account_lifecycle_test.dart
test/search_html_preparation_test.dart
test/cooked_html_search_highlight_test.dart
test/site_emoji_test.dart
test/emoji_parity_surfaces_test.dart
test/markdown_highlight_test.dart
test/markdown_highlight_incremental_test.dart
test/post_flag_editor_ownership_test.dart
test/post_flag_widgets_test.dart
```

The full suite was not run, following `AGENTS.md`. Verification uses unit and
widget tests; no native release build or manual device check was performed.
