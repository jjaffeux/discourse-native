# Ten further architecture improvements

Baseline: `3aa6de90e`, after the first ownership round and newer channel-panel
work. These changes strengthen existing owners and contracts. The proof is
observable state, errors, resource counts and I/O counts; no application latency
or frame-rate improvement is inferred from those counts.

## Improvements and proof

| # | Architecture change | Baseline problem | Advantage and primary proof |
| --- | --- | --- | --- |
| 1 | Destination bookmarks share committed state and the full transaction lane per persistence owner. | Distinct replacement stores serialize physical writes but construct them from divergent domain snapshots, losing previously committed routes. | Page and category additions from different stores survive reload together; failed writes remain unpublished and cannot contaminate the next store's transaction. `destination_bookmarks_store_test.dart`: shared-owner tests. |
| 2 | Push-ID caches carry a shared persistence mutation version. | Replacing a credential store shares the write queue but leaves the old store's retained or hydrating push identity valid. | Both retained and pending reads answer the new token after another store writes it. `secure_store_test.dart`: shared-owner invalidation and overtaken-read tests. |
| 3 | Queued GET transmission and coalescing consume one admitted request snapshot. | The request key retains the original headers while dispatch later reads a caller-mutated request. | A queued JSON request remains JSON after its original request is changed to HTML; another JSON consumer joins that one transfer. `http_basic_auth_test.dart`: admitted wire snapshot. |
| 4 | Settings hydration shares pending I/O within its accepted mutation generation. | Concurrent readers repeat the same seven persistence calls. | Two concurrent readers use seven field reads instead of fourteen; a later explicit refresh still rereads storage. Sharing must not let a read submitted after another store's write join an older hydration. `app_settings_store_test.dart`: pending hydration and write-order proofs. |
| 5 | The origin scheduler supervises injected priority capabilities in their submitter context. | A failing priority resolver throws from lease cleanup and strands queued work; queued resolvers run in the releaser's zone. | Only the failed admission is rejected, with its original error/stack; peers and retries proceed. Priority runs under `submitted`, not `released`. `origin_request_gate_test.dart`: capability failure and context tests. |
| 6 | `FrameSafeNotifier` owns logical retirement separately from native listener cleanup. | Disposing from an admitted listener, including a nested notification, raises Flutter's dispose-during-notify assertion. | Already-admitted listeners finish; new notifications and value writes are inert; native disposal completes before the outer dispatch returns. `frame_safe_notifier_test.dart`: retirement tests. |
| 7 | Plugin host bindings reject duplicate namespace claims at composition. | A map comprehension silently lets the last binding replace the first. | Composition rejects duplicate owner/name claims before a session can observe ambiguous capabilities. `plugin_admission_contract_test.dart`. |
| 8 | Reified plugin keys validate values where they enter host, service and model storage. | Covariant generic erasure allows an integer under a string key; the failure appears only when a distant consumer casts. | The producer boundary rejects incompatible root/scoped ports, services and model values, including transformed records. Service installation still rolls back owned lifecycles. `plugin_admission_contract_test.dart`. |
| 9 | Event subscription admission remains owned until its returned handle is committed. | A closed controller can subscribe again, or a subscribe callback can retire the owner before its returned subscription is stored. | Closed acquisition admits no subscription; subscribe-time retirement cancels the newly returned resource instead of retaining it. `event_controller_admission_test.dart`. |
| 10 | Event presentation consumes a domain API; the concrete adapter owns calendar protocol and validation. | Calendar export reaches through `controller.api.transport`, knows the ICS endpoint and validates wire format in presentation orchestration. | An in-memory domain API supports controller loading and calendar export without HTTP or JSON fixtures; the adapter retains protocol and malformed-calendar tests. `event_domain_api_test.dart`. |

## Shape and synthesis

Two source reviewers compared competing shapes before implementation. The
selected shape keeps responsibilities with existing owners rather than adding a
generic task manager. It also keeps the previous public result contracts.

For bookmarks, one private owner holds entries, readability, transaction queue
and snapshot writer together. Sharing only the queue would still permit stale
snapshots. Reloading before every mutation would add I/O and a new failure
surface. Public store identities remain distinct; memory stores remain isolated.

Push caches share authority rather than globally retaining the token value.
This invalidates all stores on writes while newly opened stores still consult
actual persistence. Settings share hydration only for compatible mutation
history and release the pending slot after completion, preserving refresh.

The scheduler owns failure cleanup for injected priority code through the same
queued-removal path as cancellation. The callback's synchronous zone binding
needs no asynchronous error-zone bridge. Frame-safe notification owns dispatch
depth; caller guards cannot repair the inherited notifier's disposal assertion,
and deferred microtask cleanup would retain listeners beyond the dispatch.

Plugin key-local `accepts` checks retain the key's actual generic type through
an erased `Key<Object>` reference. A global generic helper would infer `Object`
and miss the corruption. Namespace equality remains owner/name; duplicate
claims are rejected separately. These checks validate each supplied key's actual
reified type; they do not globally unify independently reconstructed keys with
different types and equal names. Type errors name the key and types, not payload
contents. Unknown persisted namespaces keep their existing opaque contract.

Event calendar transport, endpoint construction and format acceptance belong
together in `DiscourseEventApi`; export retains account/view lifetime and native
save orchestration. The domain `EventApi` exposes no transport. Existing
constructor callers migrate to the concrete adapter, with no compatibility
constructor retaining the old coupling.

## Reconciliation and limits

The video-cancellation candidate was dropped because existing tests expressly
preserve late credential failures after retirement. That code is unchanged.
Independent review also found that blindly sharing settings hydration across a
replacement store's write would violate read-after-write ordering; the shared
mutation authority is part of the design, not an exception to that contract.

Bookmark and push coordination is scoped to shared in-process persistence
identity. Different wrappers for the same physical store and separate processes
are outside that contract. GET admission copies headers once. Settings I/O
counts describe one overlapping pair and a later refresh, not a wall-time
speedup. Notification retirement permits callbacks already in an admitted
dispatch to finish, as Flutter's notifier contract requires.

## Validation

The new runtime checks produced **19 failures against unchanged baseline code**:
six data checks, four notifier/scheduler checks, and nine plugin/event checks.
The event domain interface proof separately produced the baseline compiler
error that final `EventApi` cannot be implemented outside its library.

The combined implementation passed **686 tests across 35 explicit files**.
Analysis of all **25 changed Dart files** reported **No issues found**.
Formatting verified 25 files without changes; `git diff --check` passed.
Independent read-only review covered the data, foundational and plugin/event
changes, including the settings ordering correction described above.

Reproduce the focused integration run from the repository root:

```sh
flutter test --no-pub \
  test/frame_safe_notifier_test.dart \
  test/frame_safe_notifier_headless_test.dart \
  test/origin_request_gate_test.dart \
  test/architecture_ownership_contract_test.dart \
  test/request_coordinator_test.dart \
  test/byte_cache_request_test.dart \
  test/topic_read_controller_test.dart \
  test/user_summary_controller_test.dart \
  test/topic_presentation_controller_test.dart \
  test/destination_bookmarks_store_test.dart \
  test/secure_store_test.dart \
  test/http_basic_auth_test.dart \
  test/app_settings_store_test.dart \
  test/destination_bookmarks_shell_test.dart \
  test/destination_bookmarks_ui_test.dart \
  test/app_settings_controller_test.dart \
  test/startup_settings_restore_test.dart \
  test/push_registration_test.dart \
  test/authenticator_test.dart \
  test/discourse_transport_contract_test.dart \
  test/discourse_transport_redirect_test.dart \
  test/plugin_admission_contract_test.dart \
  test/plugin_runtime_test.dart \
  test/plugin_data_codec_test.dart \
  test/plugin_composer_metadata_test.dart \
  test/assigned_group_controller_test.dart \
  test/event_controller_admission_test.dart \
  test/event_domain_api_test.dart \
  test/event_controller_test.dart \
  test/event_api_test.dart \
  test/event_export_test.dart \
  test/bundled_plugin_manifest_test.dart \
  test/plugin_static_catalog_test.dart \
  test/plugins/chat/chat_plugin_data_test.dart \
  test/plugin_user_metadata_test.dart
```

The full suite is left to CI, per `AGENTS.md`.
