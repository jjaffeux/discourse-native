# Ten proven bug fixes

All ten bugs reproduced against unchanged production at `ecafcb48a`.
Twelve focused regression tests failed for the expected behavior mismatches.
Two poll bugs each have both a model check and an actual widget semantics check.
The integrated fixes passed all 711 tests across eighteen directly related files.

| # | Reproduction and observed failure | Fixed behavior and cause | Regression test |
| --- | --- | --- | --- |
| 1 | Preview raw `Read [Dart](https://en.wikipedia.org/wiki/Dart_(programming_language)) today.`. The preview retains all link markup. | Shows `Read Dart today.`. The preview now uses the existing balanced Markdown token reader instead of a flat regular expression. | [post_plain_text_test.dart](../../test/post_plain_text_test.dart), `raw previews retain labels of balanced links` |
| 2 | Parse `[guide](<https://example.com/one(two>)` in the link editor. It returns no link. | Returns the usable URL `https://example.com/one(two`. Parentheses inside an angle-delimited destination are literal. | [composer_link_parser_test.dart](../../test/composer_link_parser_test.dart), `angle destinations allow literal parentheses` |
| 3 | Edit `<!--\n> literal\n-->\n> actual`. Quote prefixes are reported at offsets `[5, 19]`, including the comment. | Only offset `[19]` is projected. Comment text remains literal during quote projection and caret navigation. The prefix reader now excludes existing literal-container ranges. | [composer_blockquote_test.dart](../../test/composer_blockquote_test.dart), `comments retain literal quote-looking source` |
| 4 | Expand a backward selection crossing part of a quote, with base `41`, extent `21`, and default `isDirectional=false`. Expansion changes the anchor to `7` and caret to `41`. | Retains base `41`, expands extent to `7`, and preserves affinity. Selection direction follows base and extent offsets rather than the directional flag. | [composer_quotes_test.dart](../../test/composer_quotes_test.dart), `quote expansion preserves backward selection` |
| 5 | Receive an asset with Date `12:00`, Expires `13:00`, and Age `7200`. It is incorrectly cached until `13:00`. | The already-stale response is not persisted. An Age of `1800` leaves freshness only until `12:30`. The Expires branch now subtracts upstream Age from the response lifetime. | [byte_cache_test.dart](../../test/byte_cache_test.dart), `Expires freshness accounts for upstream Age` |
| 6 | Receive a guest-session cookie with positive Max-Age and past Expires, then a deletion with Max-Age `-1`. Subsequent request cookies are `[null, '_forum_session=deleted']`. | Requests carry `['_forum_session=anonymous', null]`. Max-Age takes precedence over Expires, and nonpositive Max-Age deletes the cookie. | [dsa_notices_api_test.dart](../../test/dsa_notices_api_test.dart), `guest cookies honor Max-Age before Expires` |
| 7 | A forum on `forum.example.com` sets a session cookie for Domain `example.com`. The next guest verification request has no Cookie header. | The next request retains the session cookie. Domain matching accepts exact hosts and dot-delimited parents, case-insensitively, while rejecting unrelated domains, deceptive suffixes, and IP suffix matches. | [dsa_notices_api_test.dart](../../test/dsa_notices_api_test.dart), `guest sessions accept matching parent cookie domains` |
| 8 | Render a poll option containing `Soup<br>and bread`. Its accessible label is `Soupand bread`. | The actual semantics tree contains `Soup and bread`. The card's filtered HTML now passes through the existing SDK text decoder, which retains block boundaries. | [poll_card_test.dart](../../test/poll_card_test.dart), `poll option semantics separate line breaks` |
| 9 | Render an emoji-only poll option with image alt text `:smile:`. It has no matching accessible label. | The actual semantics tree contains `:smile:`. The decoder preserves emoji image alt text after the existing hidden-content and disclosure filtering. | [poll_card_test.dart](../../test/poll_card_test.dart), `emoji-only poll options have semantics labels` |
| 10 | Search categories with 249 ASCII letters followed by an emoji. The transmitted JSON term ends in lone high surrogate `55357`, which Ruby's JSON parser rejects as an incomplete surrogate pair. | Keeps complete graphemes within the existing 250 UTF-16-unit budget. Combining-character boundaries and unchanged 250-unit ASCII input are also covered. | [discourse_api_test.dart](../../test/discourse_api_test.dart), `category searches retain complete Unicode characters` |

Each named test above starts with `regression nov8:`. The HTTP contracts for
rows 5 through 7 are [RFC 9111 freshness and age](https://www.rfc-editor.org/rfc/rfc9111.html#section-4.2.3),
[RFC 6265 cookie expiration](https://www.rfc-editor.org/rfc/rfc6265.html#section-5.3),
and [RFC 6265 domain matching](https://www.rfc-editor.org/rfc/rfc6265.html#section-5.1.3).

## Reproduce the focused checks

Run the final tests with original production files to reproduce twelve failures,
or run them on the fixed branch to verify twelve passes.

```sh
flutter test --no-pub --reporter expanded --concurrency=1 \
  test/post_plain_text_test.dart \
  test/composer_link_parser_test.dart \
  test/composer_blockquote_test.dart \
  test/composer_quotes_test.dart \
  test/byte_cache_test.dart \
  test/dsa_notices_api_test.dart \
  test/poll_test.dart \
  test/poll_card_test.dart \
  test/discourse_api_test.dart \
  --plain-name 'regression nov8:'
```

The independent baseline checkout retained original production files throughout.
One run recorded `+0 -11: Some tests failed.` for rows 1 through 9, including
both poll model checks. A separate category API run recorded
`+0 -1: Some tests failed.` for row 10. Each failure matched the value or
semantics mismatch described above, rather than a loading or compilation error.
The final serial run recorded `+12: All tests passed!` with exit code 0.

Regression-only commits precede production fixes in this branch's history.
The original production revision is `ecafcb48a`.

## Integrated verification

The following explicit-path run passed `+711: All tests passed!` with exit code 0.

```sh
flutter test --no-pub --reporter expanded \
  test/post_plain_text_test.dart \
  test/composer_link_parser_test.dart \
  test/composer_blockquote_test.dart \
  test/composer_blockquote_decoration_test.dart \
  test/composer_link_nested_labels_test.dart \
  test/composer_inline_formatting_test.dart \
  test/markdown_highlight_test.dart \
  test/composer_quotes_test.dart \
  test/composer_quote_parser_test.dart \
  test/composer_quote_panel_test.dart \
  test/byte_cache_test.dart \
  test/byte_cache_store_test.dart \
  test/dsa_notices_api_test.dart \
  test/poll_test.dart \
  test/poll_card_test.dart \
  test/poll_card_session_test.dart \
  test/discourse_api_test.dart \
  test/taxonomy_directory_test.dart
```

Independent review found that replacing a whole Markdown link copied BBCode
formatting tags inside its label into the preview. An additional regression
reproduced `A [b]bold[/b] link` instead of `A bold link`. The correction removes
the link's delimiters and destination as separate spans, allowing existing
formatting removal to process the label. It is included in the 711 passing checks.

Static analysis found no issues in the eighteen changed Dart files. Formatting
and `git diff --check` passed. The full suite was not run, following `AGENTS.md`.
Verification covers actual HTTP request bodies, request cookie headers,
Flutter semantics nodes, and composer parsing and selection behavior. No native
release build or physical-device screenreader session was performed.
