# Third batch of ten verified bug fixes

All ten new regression tests failed against production code at `3aa6de90e`.
The final baseline run selected tests with the `regression:` prefix: ten new
failures and one passing test from the preceding batch. Each new failure
matched the broken behavior below. The repaired code passed all 393 tests
across 25 directly related files. Analysis and formatting passed for all
20 changed Dart files.

| # | Reproduction | Observed before the fix | Correct result | Regression test file |
| --- | --- | --- | --- | --- |
| 1 | Change a report's date range while its loading notification is dispatched. | The obsolete load still reads credentials, producing two reads instead of one. | Only the current load reads credentials. | [report_test.dart](../../test/report_test.dart), `superseded report skips obsolete credential reads` |
| 2 | Validate a notice explanation containing 25 supplementary Unicode characters. | Validation returns true because 25 characters occupy 50 UTF-16 code units. | Enforce the server's 50-character minimum using Unicode scalar counts. Valid names containing 200 supplementary characters also pass. | [dsa_notice_models_test.dart](../../test/dsa_notice_models_test.dart), `notice length validation counts Unicode characters` |
| 3 | Parse a chat search window containing two messages and one null slot. | Both search surfaces report two consumed slots instead of three. | Count all three server slots before rejecting unusable rows, so the next offset advances correctly. | [chat_search_test.dart](../../test/chat_search_test.dart), `chat search counts every raw pagination slot` |
| 4 | Build a search-result link for a tag whose slug is `%E6%97%A5%E6%9C%AC%E8%AA%9E`. | Decoding the resulting path once still yields the percent-encoded slug. | The decoded segment is `日本語`, with or without a tag ID. Raw fallback names retain their literal percent signs. | [search_results_test.dart](../../test/search_results_test.dart), `encoded tag slugs are encoded once in search links` |
| 5 | Quote a Prometheus alert with a fractional UTC opening timestamp. | The quote contains no date block the native date parser can read. | Emit a supported time with an explicit UTC source zone. The quote resolves to `2020-07-27T17:26:49Z`. The alert record retains its original wire precision. | [alert_data_test.dart](../../test/alert_data_test.dart), `quoted alert timestamps resolve as native local dates` |
| 6 | Fail the private-message recipient lookup during its debounce callback. | `Bad state: network unavailable` escapes as an uncaught asynchronous error. | Keep the query editable, contain the lookup failure, and allow the same query to succeed on retry. | [composer_recipient_lookup_test.dart](../../test/composer_recipient_lookup_test.dart), `recipient lookup contains network failures and retries` |
| 7 | Parse a YouTube URL with `start=0s&t=30s`. | Playback starts at 30 seconds. | Honor the explicit zero rather than taking the fallback timestamp. Empty and oversized time components remain invalid. | [youtube_video_test.dart](../../test/youtube_video_test.dart), `an explicit zero YouTube time overrides fallback timestamps` |
| 8 | Read an audio onebox with `src="uploads/recording.mp3"` on `https://forum.test/community`. | The source becomes `https://forum.test/uploads/recording.mp3`. | Resolve it to `https://forum.test/community/uploads/recording.mp3`, matching the forum-directory contract. | [audio_onebox_test.dart](../../test/oneboxes/audio_onebox_test.dart), `relative onebox audio retains the forum subfolder` |
| 9 | Load update preferences whose last check is a year in the future, as after correcting the device clock. | No automatic update check occurs. | Treat the future timestamp as due for a fresh check. | [update_test.dart](../../test/update_test.dart), `a future saved check does not disable automatic updates` |
| 10 | Read `/u/sam/` as a profile root on either a root or subfolder forum. | The native card parser returns null. | Resolve `sam` and open the native card. `/u/sam/activity/` still belongs to the profile subpage. | [user_card_test.dart](../../test/user_card_test.dart), `trailing-slash profile roots still open native cards` |

The notice character limits match core's `Dsa::SubmitNotice::Contract` in
`app/services/dsa/submit_notice.rb`. The existing chat corpus now bounds the
raw server window before filtering, rather than reading extra rows past that
window. The existing alert quote assertion now expects markup that its native
consumer accepts.

The focused command selects the ten new tests and the preceding report test:

```sh
flutter test --no-pub --reporter expanded \
  test/report_test.dart \
  test/dsa_notice_models_test.dart \
  test/chat_search_test.dart \
  test/search_results_test.dart \
  test/alert_data_test.dart \
  test/composer_recipient_lookup_test.dart \
  test/youtube_video_test.dart \
  test/oneboxes/audio_onebox_test.dart \
  test/update_test.dart \
  test/user_card_test.dart \
  --plain-name 'regression:'
```

The 393-test run used those ten files plus the following related suites:

```text
test/report_page_test.dart
test/dsa_notice_form_test.dart
test/dsa_notice_presentation_test.dart
test/chat_search_controller_test.dart
test/chat_search_view_test.dart
test/global_search_panel_test.dart
test/alert_tables_test.dart
test/prometheus_alert_receiver_plugin_test.dart
test/composer_recipients_search_test.dart
test/youtube_player_surface_test.dart
test/oneboxes/embedded_onebox_test.dart
test/oneboxes/lazy_embedded_video_test.dart
test/user_card_popover_test.dart
test/user_card_account_lifecycle_test.dart
test/user_card_target_accessibility_test.dart
```

The full suite was not run, as required by `AGENTS.md`. Verification used
focused unit and widget tests. No native release build or manual device check
was performed.
