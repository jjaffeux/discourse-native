# Ten ownership boundary improvements

The app already separates HTTP adapters, controllers, persistence, media caches,
and plugin services. This change strengthens those owners where work crosses
an asynchronous boundary. The baseline is `138afd4e3`. Gains below are observable
contracts, not estimates of startup speed or frame performance.

## Changes and proof

| # | Architecture improvement | Before | Proven advantage and test |
| --- | --- | --- | --- |
| 1 | `PreferenceSnapshots` registers a completer before invoking the reader. | Synchronous reentry starts another hydration and receives 99 while the first caller receives 7; synchronous exceptions escape the Future API. | Both consumers receive 7 from one reader; thrown reader errors settle the returned future and allow retry. `architecture_ownership_contract_test.dart`: hydration admission and failure tests. |
| 2 | `CoalescingSnapshotWriter` captures execution context per accepted save and bridges completion into the drain's zone. | A pending replacement writes under the first writer's zone (`first`) instead of its submitter's (`new`). | The two physical writes run under `first` and `new`; a failed queued write in a separate error zone settles its caller and leaves no uncaught error. Existing coalescing/order contracts remain. `architecture_ownership_contract_test.dart`: writer zone tests. |
| 3 | `FileByteCacheStore` owns its encoded snapshot before its first await. | Mutating submitted bytes immediately changes durable `[1,2,3]` to `[99,2,3]`. | Reopening the file returns `[1,2,3]`. The encoded buffer is moved before directory creation; no second body copy is introduced. `architecture_ownership_contract_test.dart`: file cache submission. |
| 4 | `SiteLifecycle` gives each retirement subscription a distinct registration identity. | Registering the same callback twice and removing one removes both registrations: cleanup count 0. | Removing one subscription, even twice, leaves the other cleanup active: count 1. Existing failure isolation and reentrant successor tests remain. `architecture_ownership_contract_test.dart`: retirement subscription identity. |
| 5 | `OriginRequestGate` has one iterative drain owner and revises selection after callback-driven queue changes. | Reentering admission from a priority callback grants two leases against capacity one. | The nested lease stays pending until the first releases. A callback may also reject its own queue entry through cooldown without stale-index removal or stranding other origins. `architecture_ownership_contract_test.dart`: gate reentry and cooldown tests. |
| 6 | HTTP Basic-auth retention captures its normalized origin set at submission. | Changing the submitted list from A to B before queued work runs durably removes A's credentials. | Reopening storage retains A and removes B, matching the submitted intent. URI errors remain Future failures. `architecture_ownership_contract_test.dart`: retention submission. |
| 7 | Site image publication owns one copied, read-only byte buffer. | Any consumer can overwrite the bytes shared by the image cache. | Published mutation throws; the next hit shares the same image and original bytes with exactly one transfer. `site_image_repository_test.dart`: published image bytes. |
| 8 | Badge presentation depends on a domain interface; `DiscourseBadgesApi` owns HTTP and wire parsing in its own file. | `BadgesApi` is a final concrete transport adapter, so an independent typed implementation is forbidden. | A controller loads a typed in-memory catalog without HTTP, URL strings or JSON fixtures. Existing adapter-backed badge tests still verify protocol and pagination. `badges_controller_test.dart`: domain API test. |
| 9 | Each AI summary request owns a detachable lease-retirement subscription. | Quiet streams and pending POSTs retain live subscriptions and unresolved results after account retirement until another event or deadline. | Retirement immediately fails the request and removes its live subscription, both during a quiet stream and while HTTP is still pending. Late HTTP failures remain observed. `discourse_ai_summary_test.dart`: quiet AI retirement tests. |
| 10 | `UserSummary` owns all eight immutable collections at construction. | Its `@immutable` public constructor aliases supplied lists; clearing them empties all eight published collections. Only JSON construction freezes them. | Clearing every input leaves all eight collections unchanged; mutation through each published list is rejected. JSON parsing delegates freezing to that single boundary. `user_summary_model_test.dart`: construction snapshots. |

The baseline runs reproduced the failures for nine behavior changes (eleven
assertion failures across the selected cases, including two hydration and two AI
cases). The badge advantage is a compile-time dependency capability demonstrated
by the typed fake, rather than a runtime defect. Additional queue mutation and
cross-error-zone cases protect design risks discovered during review.

## Design and synthesis

Callers keep using `ensure`, `save`, byte-cache writes, retirement subscriptions,
request leases, retained origins, images and AI requests. Their existing owners
now enforce admission, snapshot and retirement rules at those boundaries. Badge
composition constructs `DiscourseBadgesApi(transport)`; `BadgesController` sees
only `BadgesApi.catalog`, `badge` and `grants`, returning domain models.

Two read-only design reviewers compared owner-local changes with a centralized
task/session manager. Both chose existing owners: a generic manager would still
need callbacks for heterogeneous credential, byte, query and subscription rules.
The synthesis uses per-submission execution context, registers AI retirement
after pending-map admission, and retries scheduler selection when callback-driven
queue changes invalidate its scan. A separate cross-judge was skipped because
the available panel shares the GPT model family.

## Reconciliation and tradeoffs

- Image publication adds one bounded copy per decoded image. Cache hits share
  it; no memory reduction is claimed.
- Summary construction loses `const` construction so it can own its inputs.
  All callers are migrated; JSON parsing drops its redundant list freezing.
- Snapshot hydration preserves interaction precedence and the caller-result
  contract for reads forgotten while pending.
- A sidebar candidate was dropped because an existing test expressly retains
  the caller's hydration result after forgetting.
- A chat browse candidate was dropped when related tests established that
  dispatched pages intentionally settle before the next debounced query.
  Chat code and tests are unchanged.
- AI request retirement observation is attached only for active controllers;
  disposed controllers retain their direct cancellation path.

## Validation

All **422 tests passed across 26 explicit files**: 301 owner/consumer tests and
121 AI, summary UI and preference caller tests. Analysis of all 20 changed Dart
files reported **No issues found**. Formatting and `git diff --check` passed.

The existing AI session-close test also stalled with the unchanged production
implementation. It now closes the plugin session on the real async scheduler
and pumps the synchronously cancelled reload before awaiting its assertion.
Its cancellation and single-request assertions are unchanged.

Reproduce from the repository root:

```sh
flutter test --no-pub \
  test/architecture_ownership_contract_test.dart \
  test/user_summary_model_test.dart \
  test/user_summary_controller_test.dart \
  test/plugin_user_summary_identity_test.dart \
  test/badges_controller_test.dart \
  test/badges_navigation_test.dart \
  test/badges_page_test.dart \
  test/badge_recipients_loading_test.dart \
  test/site_image_repository_test.dart \
  test/site_image_request_test.dart \
  test/site_lifecycle_test.dart \
  test/origin_request_gate_test.dart \
  test/http_basic_auth_test.dart \
  test/byte_cache_store_test.dart \
  test/coalescing_snapshot_writer_test.dart \
  test/topic_sidebar_store_test.dart \
  test/sidebar_section_store_test.dart \
  test/request_coordinator_test.dart \
  test/byte_cache_request_test.dart \
  test/byte_cache_request_pool_test.dart \
  test/composer_layout_store_test.dart \
  test/recent_destinations_store_test.dart \
  test/discourse_ai_summary_test.dart \
  test/user_summary_test.dart \
  test/forum_settings_test.dart \
  test/forum_settings_page_test.dart
```

The full suite is left to CI, per `AGENTS.md`.
