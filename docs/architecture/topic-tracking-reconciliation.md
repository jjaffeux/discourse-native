# Topic tracking reconciliation

`TopicTrackingReconciler` owns the tracking protocol for one account at one site. Private site live sessions own MessageBus startup, subscriptions, snapshot transport, and retry capabilities. `NotificationPreferenceTransactions` owns notification write queues, current-user category preference merging, and refresh admission. `ShellController` retains navigation and adapts the owner to current-user persistence, taxonomy, and live-session transport.

## Usage

```dart
final ticket = tracking.beginSnapshot();
tracking.accept(busMessage, user: currentUser, config: siteConfig);
tracking.markRead(topicId, position);
tracking.completeSnapshot(ticket!, report);
```

Bootstrap capture starts before its transport request. Category changes replace the active report ticket. After authoritative category preferences arrive, `preferencesReady` removes preceding replay events. The shell checks its lease after credential IO and checks lease and user identity around transport and store publication. The reconciler also checks account authority and exact ticket identity.

A native notification choice has an opaque `TopicTrackingChoice`. The notification preference owner serializes its HTTP write, then settles that token. Older successful writes advance the latest choice's rollback baseline without settling its overlay. Topic-channel echoes update the baseline while preserving the pending selection. Rejection changes only notification level on the current row. The notification preference owner releases a choice when its write tail finishes.

`NotificationPreferenceTransactions` groups each account's queues and shared reconcilers in one private session bound to a `SiteLease`. Each topic queue keeps its latest attempt and finishing tail. The session keeps one shared category write tail because category responses include account-wide inherited mute lists. Category queues retain each latest attempt and last confirmed level. Admission installs queue ownership before optimistic Store publication. Lease retirement removes only the original session, so old completions cannot clear replacement-account state. The owner reads credentials through `AccountRequestSession` and reuses the existing tracking and current-user reconcilers.

The owner merges category membership lists against the latest user and sends the result through a narrow current-user publication port. Taxonomy still owns category publication. The owner opens the replacement tracking ticket and constructs the fenced preference-read callback. The live session retains snapshot transport and retry state. Confirmed category POSTs remain successful when subsequent persistence or refresh fails.

## Live connection lifetime

Each live session holds startup completion until HTML bootstrap settles, so later JSON account refreshes run second. An assembling tracker is available for scoped plugin handles, while polling requires a ready tracker with all core, plugin, and visible-topic channels registered. One desired-state policy governs startup, foreground changes, retention, and resume. Anonymous readers on private forums never qualify, even with retention. Retirement closes the assembling or ready tracker and releases its retry capability. Callbacks require the captured startup attempt or exact ready tracker as well as the account lease.

## Ordering contract

1. Admit bus events once using the account's shared incoming-topic filter. Replay cannot renew hints, admit an earlier rejected event, or expire an accepted event.
2. Measure the original report length before replay. Replay accepted events in arrival order.
3. Reapply local read positions, then pending notification choices, without replacing other row metadata.
4. Merge omitted rows against the current live state. Complete reports settle omitted new and unread rows. Reports at the server limit retain omitted settled rows only.
5. Install the result, advance revision, and close the replay window. Sparse live rows never establish snapshot readiness.

Local choices completed before a delayed bootstrap remain in the replay journal after their pending token is released. Pending-choice lifetime and report-replay lifetime are distinct. Category preference barriers clear earlier observations while retaining pending choices and local read positions.

## Shape and alternatives

The mutable session candidate is the base. It retains `TopicTrackingState` as the row and counter engine. One owner holds the active ticket, snapshot readiness, retry phase, accepted-event journal, local read positions, and notification choice tokens. Read-only row and counter queries expose projections without exposing the mutable row engine. This follows Model the Domain and Minimize Reader Load: callers feed facts rather than reconstructing precedence from shell maps.

The competing reducer design separated observed and effective row tables. It scored well for explicit overlays, but required extracting shared row storage and indexes before migrating production. The independent comparison preferred the session design for its smaller migration and preserved row behavior. The selected design takes the reducer's distinct pending and completed-choice lifetimes and opaque settlement tokens, without duplicating aggregate storage.

Transport retry closures belong to each live session because they capture credentials and API arguments. `failSnapshot` records retry phase and rejects stale failures. The live session opens the next ticket before the shell admits its triggering message. This keeps transport concerns outside the reconciler while concentrating load authority inside it.

## Implementation reconciliation

The design panel proposed separate basis classes and one method per load cause. The implementation uses snapshot readiness plus the orthogonal load phase, and one ticket operation for initial, retry, resume, and category reads. This preserves serving a loaded basis during refresh with fewer caller methods. Bootstrap has its own capture token because it may precede HTTP fallback.

The existing partial-report policy and explicit acknowledged mark-unread reset are preserved. This refactor makes no performance claim and adds no notifier. The shell retains active-site notification checks and its microtask coalescing. The transaction coordinator and its effect ports introduce no notifier.

## Validation

`topic_tracking_reconciler_test.dart` pins pure delayed report reconciliation, choice settlement, category barriers, admission-time replay, retry, truncation, and retirement. `site_live_sessions_test.dart` pins reentrant retention before the first poll, hidden bootstrap ordering, replacement during bootstrap, failed registration cleanup, and retirement during attachment. The owning shell notification, muted tracking, async ordering, unread, and rebuild-isolation tests exercise production adapters and publication.

`notification_preference_transactions_test.dart` constructs the owner without a shell or Flutter binding. It pins reentrant admission, account-wide category ordering, lease retirement during writes and credential reads, unknown write outcomes, and confirmed success after publication or refresh failure.
