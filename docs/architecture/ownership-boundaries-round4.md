# Ten further architecture improvements, round four

Baseline: `440be441a`. This round excludes the thirty changes in the earlier
ownership reports. Evidence below concerns admitted work, result authority,
resource ownership and operation counts, rather than inferred wall-time gains.

## Improvements and proof

| # | Architecture improvement | Before | Advantage and primary proof |
| --- | --- | --- | --- |
| 1 | Each bootstrap instance owns one admitted startup attempt. | Repeated or host-reentrant calls reinstall plugins, launch again and reschedule initialization; retry after failure repeats partial side effects. | Initialization/launch/scheduling occur once. Later calls after fatal failure rethrow its original error and stack without retrying partial installation. `app_bootstrap_test.dart`. |
| 2 | Notification ingress owns source replacement through cancellation and subscription callbacks. | Reentry from `onCancel` or `onListen` can overwrite the newer subscription handle; cancellation failures escape. | Returned handles are retained only by their still-current source; superseded handles are cancelled, and optional cleanup failures cannot block replacement or shutdown. `app_runtime_test.dart`. |
| 3 | Prepared uploads admit disposal before invoking resource cleanup. | Synchronous cleanup reentry runs release twice; a thrown callback escapes the Future API and allows a later retry. | Disposal has one shared success/error and one cleanup attempt. The producer supplies cleanup, while `dispose` is its sole public invocation path. `data_architecture_round4_test.dart`. |
| 4 | Cooking execution shares one current-request admission policy. | Ordinary cooking omits the context revision checked by transient cooking and public validity checks, admitting already-obsolete requests. | An obsolete context is refused before the service is called; normal work already admitted retains its established completion contract. `data_architecture_round4_test.dart`. |
| 5 | Current-user refresh sharing retains each caller's request intent. | Interactive adoption of a background refresh cannot promote it; forced replay inherits the active task's context instead of its own callers. | An adopted interactive refresh dispatches ahead of queued background work. Pending forced work keeps a separate intent group. `data_architecture_round4_test.dart`. |
| 6 | Private staging owns its export bytes at submission. | Caller mutation during directory/file setup changes the content later passed to a save/share capability. | The staged file contains the accepted bytes and still follows existing private permissions and cleanup rules. `data_architecture_round4_test.dart`. |
| 7 | Placeholder values have distinct per-consumer leases over private shared state. | Acquisitions return the same public value, so duplicate release by one consumer consumes a peer's ownership. Closed sessions can admit reads. | Release is idempotent per lease, peers remain editable, closed sessions withdraw retained values and deny new acquisition. `plugins/discourse_placeholder/placeholder_session_test.dart`. |
| 8 | AI conversation pagination belongs to a route-local session with immutable state. | The widget owns request tokens and rows without retirement observation, and retained callbacks can admit duplicate pages. | Account retirement withdraws rows immediately; page admission and navigation use one route owner. The existing Native page consumes state and commands. `ai_conversations_session_test.dart` and `ai_conversations_homepage_test.dart`. |
| 9 | Voice batching owns immutable JSON signal envelopes. | Nested candidate/SDP collections stay caller-owned while waiting for a timer or earlier batch. | Later caller mutation cannot alter queued signaling; unsupported values fail through the Future boundary before queue mutation. `voice_signaling_test.dart`. |
| 10 | Event lifecycle dispatch traverses an admitted snapshot and rechecks each owner. | Resume/tracker callbacks can remove entries while live collections are being iterated, aborting peer dispatch. | A callback may retire a handle without concurrent modification; surviving peers still receive their eligible lifecycle work. `event_controller_admission_test.dart`. |

## Shape and synthesis

Source reviewers compared alternate ownership shapes before implementation.
The selected design uses existing owners and shared request-intent groups rather
than a general task manager. A unique placeholder lease encodes consumer
identity; clamping a shared reference count cannot identify which consumer
already released. A conversation session keeps its cursor, request and account
lease together, so widgets cannot independently change pagination authority.

Bootstrap admission precedes the first host callback. A global startup guard
would couple independent hosts, and retrying phases would need rollback that
the host API does not provide. Notification ingress detaches its old handle
before invoking cleanup, checks its source token before subscribing, and checks
again before committing the returned handle. Awaiting old cancellation would
let a stalled native source veto replacement.

Prepared upload cleanup likewise registers its result before invoking producer
code. Cooking preflight shares the context/account/config validity policy while
preserving the distinct existing completion contracts. Refresh tasks own their
intent groups separately: ordinary joins adopt active work, while forced calls
adopt the pending replay. Copying at staging and signaling admission keeps
mutable input policy at the boundary used by all callers.

## Limits and tradeoffs

- Startup is once per `AppBootstrap` instance; separately constructed instances
  remain independent. Optional deferred initialization keeps its best-effort
  failure policy.
- Already-admitted notification URLs remain ingress-owned across source
  replacement. Internal retirement and cancellation attempts do not guarantee
  native resource release when a host throws.
- Staging and signal snapshots add input-copy cost. Ordering and exact-content
  proofs do not imply an application latency or memory reduction.
- Placeholder lease APIs replace ambiguous shared-handle release; callers must
  release the lease they acquired. Already-admitted persistence work retains
  its durability/flush contract.
- Conversation retirement is account/route authority, and state remains a
  projection for existing Native controls. Historical immutable snapshots remain
  unchanged; retirement withdraws the current projection rather than scrubbing
  previously delivered data. No UI components or options are added.
- Voice validation owns JSON-compatible input and retains existing normalization;
  it does not introduce a complete signaling schema validator. Event dispatch
  guarantees cover the touched resume/tracker traversals, rather than arbitrary
  host cancellation failures.

## Validation

The unchanged baseline runs produced **21 runtime assertion failures**: five
startup/ingress cases, six data-owner cases, and ten plugin cases. Additional
preservation tests cover already-admitted normal cooking, separate refresh
intent sources, placeholder close listeners, and stale route commands.

The combined run passed **862 tests across 32 explicit files**. Analysis of all
**20 changed Dart files** reported **No issues found**. Formatting and
`git diff --check` passed. Independent read-only review covered every unit and
its real caller contracts, including the scope limits above.

Reproduce from the repository root:

```sh
flutter test --no-pub \
  test/app_bootstrap_test.dart \
  test/app_runtime_test.dart \
  test/app_lifecycle_test.dart \
  test/app_theme_test.dart \
  test/startup_load_failure_test.dart \
  test/forum_startup_test.dart \
  test/data_architecture_round4_test.dart \
  test/current_user_refresh_test.dart \
  test/application_cooking_test.dart \
  test/application_cooking_worker_test.dart \
  test/private_file_staging_test.dart \
  test/composer_upload_preparation_test.dart \
  test/composer_media_preparation_test.dart \
  test/composer_image_optimizer_test.dart \
  test/composer_video_optimizer_test.dart \
  test/current_user_freshness_test.dart \
  test/request_intent_test.dart \
  test/request_coordinator_test.dart \
  test/composer_upload_attachment_test.dart \
  test/composer_upload_submission_test.dart \
  test/event_export_test.dart \
  test/event_export_boundary_test.dart \
  test/image_download_test.dart \
  test/plugins/discourse_placeholder/placeholder_session_test.dart \
  test/plugins/discourse_placeholder/discourse_placeholder_widget_test.dart \
  test/ai_conversations_session_test.dart \
  test/ai_conversations_homepage_test.dart \
  test/voice_signaling_test.dart \
  test/voice_controller_test.dart \
  test/event_controller_admission_test.dart \
  test/event_controller_test.dart \
  test/bundled_plugin_manifest_test.dart
```

The full suite stays with CI, per `AGENTS.md`.
