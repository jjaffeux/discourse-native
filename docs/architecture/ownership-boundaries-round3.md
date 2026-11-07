# Ten further architecture improvements, round three

Baseline: `6a7385048`. This round excludes the twenty changes in the earlier
ownership reports. Its evidence is behavioral contracts and operation/resource
counts, not estimated application latency or frame performance.

## Improvements and proof

| # | Architecture improvement | Before | Advantage and primary proof |
| --- | --- | --- | --- |
| 1 | Typed site-preference values snapshot submitted data before queueing. | A caller can mutate a submitted string list while its write waits and change the durable intent. | The admitted list survives later caller mutation. Boolean/string values keep their existing immutable representation. `data_architecture_round3_test.dart`. |
| 2 | Preference retirement supervises each hook and tracked owner independently. | One throwing retirement callback skips later owners and durable preference removal. | All remaining owners retire and stored keys are removed despite a failed peer. `data_architecture_round3_test.dart` and preference retirement suites. |
| 3 | Overview and detail reports share one immutable source registry. | Both adapters independently scan a live iterable and choose the first matching source, accepting duplicate claims. | Composition rejects duplicate/reserved names, and input-list mutation cannot reroute an admitted adapter. The host supplies the same indexed registry to both adapters. `data_architecture_round3_test.dart`. |
| 4 | Public avatar/emoji caches share one owned image value and classification/rejection implementation. | Two wrappers duplicate SVG policy and publish mutable response buffers to consumers. | Concurrent pooled consumers share one immutable value and one transfer; mutating source-response bytes cannot alter the published value. Old wrapper/classifier APIs and callers are migrated. `data_architecture_round3_test.dart`. |
| 5 | Nested Replies owns live-created-post lookup and visibility protocol in its API. | A reader widget reaches into raw transport for post identity before fetching filtered context. | One domain operation validates identity and returns only filtered tree context; core post bodies cannot become displayed content. `plugins/nested_replies/nested_replies_api_test.dart` preserves mismatched-ID and redaction behavior without driving a widget. |
| 6 | Report requests own immutable range/filter query snapshots. | A submitted selection list can change while credentials or a plugin request are pending, without a new query generation. | The API sees the admitted deeply owned filters and range, and later refresh retains that query. `report_query_ownership_test.dart`. |
| 7 | Assigned-group presentation owns authority for every command until route retirement. | Stale callbacks still load, page, select filters or navigate after presentation disposal; listener disposal can be followed by dispatch. | Closed commands are inert, and disposal during notification prevents later command dispatch while shared domain caches keep their own lifetime. `assigned_group_view_test.dart`. |
| 8 | AI summary terminal transitions release internal ownership before optional host cleanup. | A throwing subscription cancellation can skip timer/map cleanup and abandon peer requests during controller disposal. | Terminal results stay settled, deadlines and pending ownership are released, and every peer cancellation is attempted. `ai_summary_cleanup_ownership_test.dart`. |
| 9 | The identity store enforces its key invariant at mutation publication. | `merge` or `update` can return a different ID while the cell stays indexed by the old ID. | Such output is refused before ref/generation/structure publication; the original cell survives and later valid edits work. `store_test.dart`: identity-changing update/merge tests. |
| 10 | Search focus registrations have their own identity and retirement authority. | An old unregister callback removes a replacement sharing the same field, even with the same callback. A disposed search can admit new focus registrations. | Old unregisters cannot affect their successor; closing the current registration still works; a closed search cannot regain a panel or focus callback. `shell_search_controller_test.dart`: replacement and closed-owner tests. |

## Design and reconciliation

Source reviewers compared owner-local changes and shared domain owners before
implementation. Preferences keep their typed value boundary, report routing has
one immutable registry, public images have one common value/policy, and feature
controllers retain query, navigation and cleanup responsibilities. A generic
task manager would still need to expose all these different policies to callers.

The source registry captures routing names once and owns the index; optional
plugin implementations still own endpoint knowledge and parsing. Report-query
snapshots freeze nested JSON-compatible values, not just the outer map. Nested
Replies keeps core post lookup as identity metadata and filtered context as the
only visible body source. Its admin controller receives the existing category
settings service rather than reaching through nested-reply transport.

The search registry uses a unique registration object, not callback equality.
This distinguishes two registrations of the exact same field and callback.
The store captures the key once, then validates transformed identity before any
published mutation. Caller review confirmed optimistic Chat records preserve
local IDs and carry server IDs separately; canonical arrivals are inserted
independently. Identity moves use explicit removal and insertion rather than
changing a retained cell's key.

## Limits and tradeoffs

- Public image publication adds one bounded copy per parsed response. Weak
  response-identity memoization shares the value for the same response, such as
  concurrent pooled avatar/emoji loads. Separate disk reads and later transfers
  need not share identity. No memory reduction or universal deduplication is
  claimed; private site-image ownership remains unchanged.
- Store records must remain immutable with stable IDs. The guard cannot undo
  in-place mutation performed by a caller callback. Existing cell access may
  touch LRU before a rejected merge; the proof concerns refs, generations,
  structure and publication, rather than complete LRU atomicity.
- Preference retirement retains the existing best-effort policy while ensuring
  a broken observer cannot skip another owner's cleanup or disk removal.
- Feature command retirement stops new presentation-owned work; already-admitted
  shared domain work keeps its existing domain lifetime.

## Validation

Baseline runs recorded **18 runtime assertion failures**: four store/focus,
eight data, and six query/cleanup/command cases. The nested API ownership proof
separately produced baseline analyzer errors because `createdContext` did not
exist. The old reader already used filtered content; no visibility regression
is claimed for that relocation. Registry assertions were subsequently
consolidated into the two distinct duplicate/reserved composition contracts.

The final combined run passed **915 tests across 40 explicit files**. Analysis
of all **34 changed Dart files** reported **No issues found**. Formatting and
`git diff --check` passed. Independent read-only review covered all ten units,
including caller compatibility and the limits described above.

AI timer ownership tests declare the already-resolved `fake_async` 1.3.3 as a
direct development dependency. No dependency version changed; offline package
resolution passed.

Reproduce from the repository root:

```sh
flutter test --no-pub \
  test/store_test.dart \
  test/shell_search_controller_test.dart \
  test/topic_data_owner_test.dart \
  test/bookmark_transactions_test.dart \
  test/chat_thread_metadata_owner_test.dart \
  test/topic_read_controller_test.dart \
  test/topic_record_equality_test.dart \
  test/global_search_controller_test.dart \
  test/global_search_panel_test.dart \
  test/data_architecture_round3_test.dart \
  test/avatar_loader_test.dart \
  test/emoji_cache_test.dart \
  test/media_pipeline_boundary_test.dart \
  test/owned_site_preferences_test.dart \
  test/site_preference_keys_test.dart \
  test/dashboard_test.dart \
  test/report_test.dart \
  test/plugins/data_explorer/data_explorer_reports_test.dart \
  test/site_image_repository_test.dart \
  test/site_image_request_test.dart \
  test/sidebar_section_store_test.dart \
  test/sidebar_section_removal_writes_test.dart \
  test/bookmark_reminder_store_test.dart \
  test/data/recent_search_store_test.dart \
  test/dashboard_page_test.dart \
  test/dashboard_navigation_test.dart \
  test/report_page_test.dart \
  test/ui/d_avatar_test.dart \
  test/styleguide/avatar_examples_test.dart \
  test/composer_emoji_artwork_test.dart \
  test/report_query_ownership_test.dart \
  test/ai_summary_cleanup_ownership_test.dart \
  test/discourse_ai_summary_test.dart \
  test/assigned_group_view_test.dart \
  test/assigned_group_controller_test.dart \
  test/plugins/nested_replies/nested_replies_api_test.dart \
  test/plugins/nested_replies/nested_replies_admin_test.dart \
  test/plugins/nested_replies/nested_replies_services_test.dart \
  test/plugins/nested_replies/nested_replies_reader_test.dart \
  test/bundled_plugin_manifest_test.dart
```

The full suite remains for CI, per `AGENTS.md`.
