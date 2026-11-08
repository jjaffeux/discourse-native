# Ten further architecture improvements, round five

Baseline: `634e5e50f`. These ten changes exclude the forty improvements recorded
in prior ownership reports. Evidence concerns admitted state, ordering,
resource cleanup and independent contracts, not inferred frame-rate gains.

## Improvements and proof

| # | Architecture improvement | Before | Advantage and primary proof |
| --- | --- | --- | --- |
| 1 | Queued latest-only lookups retain their submitting execution context. | A queued autocomplete starts under its predecessor's completion context rather than its caller's intent/zone. | The newest admitted lookup executes under its own context while preserving serialization and newest-only delivery. `data_architecture_round5_test.dart` and lookup tests. |
| 2 | Linux preference operations own their filter at submission. | Mutating a caller-owned allowlist during file/lock I/O changes read projection or which keys a clear removes. | Reads and destructive clears apply the admitted prefix/allowlist snapshot. `data_architecture_round5_test.dart` and Linux preference tests. |
| 3 | Core topic-tracking enrollment is a subscription transaction. | A mid-enrollment subscription failure leaves earlier channels live and prevents retry because callback state was already committed. | Partial enrollment withdraws delivery authority, attempts cleanup of all acquired handles, resets state, and admits a healthy retry once. `site_tracker_test.dart`. |
| 4 | Bootstrap wire knowledge owns its nested current-user state and plugin-name set. | Constructor aliases nested state and names, permitting caller mutation between notification and reviewable-count consumers. | Both consumers observe the accepted immutable wire snapshot; the established mutable topic-tracking reducer remains unchanged. `data_architecture_round5_test.dart` and `site_live_sessions_owner_test.dart`. |
| 5 | Voice reactions own loader and send admission through call retirement. | Reentrant settings loads can start more than once; optimistic publication may dispose the call before its network send is invoked. | One admitted settings load is shared, and no external send starts after listener-triggered retirement. `voice_reactions_test.dart`. |
| 6 | Account activity owns child-feed admission separately from read-only lookup. | Reading named state can create child owners after disposal; a retained named-user command can start credential/HTTP work through a retired parent. | Closed parents cannot create or load children, while state reads return empty projections without admission. `account_activity_controller_test.dart`. |
| 7 | Event-directory segments share one account/query operation owner. | Separate quarter requests can capture different account sessions, and synchronous query changes after notification can still dispatch obsolete work. | Authority is checked before each segment and publication; retirement or query replacement prevents later obsolete requests and mixed-session results. `event_directory_session_test.dart`. |
| 8 | Background retention publishes claims transactionally under scoped-host authority. | Validation can revoke the owner/close the registry before claim insertion; a throwing change callback leaves an orphan claim without a returned lease. | Admission revalidates exact host authority and rolls back an undelivered claim on publication failure. `plugin_background_retention_test.dart`. |
| 9 | Pane-width flushes have an explicit durability owner. | A flush can return before an accepted pending write; overlapping writes race, and failure clears the only retry intent. | Pending flushes join, accepted physical writes serialize through the existing snapshot writer, and the latest failed width remains retryable. `panel_width_controller_headless_test.dart`. |
| 10 | Speculative prefetch completion guarantees terminal settlement and releases scheduling ownership. | A failed validity/time capability can escape admission or strand an adopted result and block the next candidate. | Speculative capability failures become misses; completion-time failures settle and release the slot. Navigation adoption keeps its existing handoff contract. `topic_prefetch_controller_test.dart`. |

## Design and reconciliation

Independent source reviewers compared owner-local and shared mechanisms before
implementation. Existing queues, snapshot writers and callback boundaries are
retained; there is no general-purpose task manager. Linux filters and bootstrap
wire data own accepted inputs. Tracker/retention admission treats external
callbacks as transaction boundaries. Activity children and calendar segments
receive explicit parent/operation authority rather than isolated UI guards. Existing result and visibility contracts remain
with their domain owners.

The pane controller reuses `CoalescingSnapshotWriter`, with a revision distinguishing
an older failed width from a newer accepted one. Unchanged flushes join pending
durability. A separate revision keeps persistence retry independent of restore
interaction tracking. Coordination remains per controller; existing persistence
adapters own cross-controller ordering.

Prefetch review rejected a completion check that reused the old list-interest
predicate after navigation adoption. The real caller deliberately clears list
interest when opening a topic. `take` now records adoption, so later list exit
cannot revoke navigation's result. Explicit cancellation/account-owner clearing
retains authority to invalidate it. A preservation test passes on both baseline
and final code; it is not counted as a new gain.

## Limits and tradeoffs

- Input snapshots add copying of admitted filters/wire collections. No latency
  or memory reduction is claimed. The topic-tracking state reducer keeps its
  established mutable contract.
- Cleanup supervision guarantees internal withdrawal and release attempts;
  a throwing external cancellation may still fail to free its own resource.
- Pane flush failures still surface to awaiting callers. This change does not
  contain errors from injected throwing writers in unawaited widget callbacks.
- Speculative misses fall back to normal topic loading. Adoption stops depending
  on former list interest, not on account cancellation or retired loader results.
- Retention rollback restores the registry's own claim/count state, not arbitrary
  side effects a change callback already performed. Voice staleness denies new
  outgoing work; it does not scrub historical settings/reaction snapshots.
- Main-checkout performance edits present when this task began are unrelated;
  they are preserved rather than staged, reverted or committed by this task.

## Validation

The existing active-room Voice widget test also stalled against unchanged
production code while awaiting close work created under its fake clock. Its
fixture now observes close completion/errors and pumps within a bounded loop,
including teardown. It retains the original UI assertions and asserts close
completion without error; the fixture correction is separate from the ten gains.

The valid gain checks reproduced **21 runtime failures** against unchanged
production code: four pane/prefetch cases, five data/foundation cases, and twelve
plugin/controller cases. A prefetch expectation that contradicted navigation
handoff was rejected during review; its replacement speculative-admission test
fails on baseline, while the handoff preservation test passes on both versions.

The combined final run passed **641 tests across 33 explicit files**. Analysis
of all **20 changed Dart files** reported **No issues found**. Formatting and
`git diff --check` passed. Independent read-only review covered every unit and
its real caller contracts; the prefetch handoff finding was fixed before
integration.

Reproduce from the repository root:

```sh
flutter test --no-pub \
  test/panel_width_controller_headless_test.dart \
  test/resizable_pane_test.dart \
  test/topic_prefetch_controller_test.dart \
  test/topic_prefetch_transport_test.dart \
  test/topic_data_owner_test.dart \
  test/sidebar_width_test.dart \
  test/composer_docking_test.dart \
  test/composer_presentation_controller_test.dart \
  test/topic_presentation_controller_test.dart \
  test/data_architecture_round5_test.dart \
  test/site_tracker_test.dart \
  test/latest_wins_queued_lookup_controller_test.dart \
  test/linux_preferences_store_test.dart \
  test/site_message_bus_bootstrap_test.dart \
  test/site_live_sessions_owner_test.dart \
  test/site_live_sessions_test.dart \
  test/topic_tracking_directory_test.dart \
  test/topic_taxonomy_selectors_test.dart \
  test/topic_tag_picker_test.dart \
  test/topic_tag_picker_authorization_test.dart \
  test/group_membership_request_source_test.dart \
  test/private_file_document_test.dart \
  test/voice_reactions_test.dart \
  test/plugin_background_retention_test.dart \
  test/account_activity_controller_test.dart \
  test/event_directory_session_test.dart \
  test/voice_reaction_controller_test.dart \
  test/voice_reaction_widgets_test.dart \
  test/account_activity_pagination_test.dart \
  test/account_activity_paging_loading_test.dart \
  test/account_activity_rollback_test.dart \
  test/event_directory_test.dart \
  test/event_directory_occurrences_test.dart
```

The full suite stays with CI, per `AGENTS.md`.
