# Topic tracking reconciliation

`TopicTrackingReconciler` owns the tracking protocol for one account at one site. `ShellController` retains HTTP requests, message subscriptions, write queues, navigation, store updates, and notification scheduling.

## Usage

```dart
final ticket = tracking.beginSnapshot();
tracking.accept(busMessage, user: currentUser, config: siteConfig);
tracking.markRead(topicId, position);
tracking.completeSnapshot(ticket!, report);
```

Bootstrap capture starts before its transport request. Category changes replace the active report ticket. After authoritative category preferences arrive, `preferencesReady` removes preceding replay events. The shell checks its lease after credential IO and checks lease and user identity around transport and store publication. The reconciler also checks account authority and exact ticket identity.

A native notification choice has an opaque `TopicTrackingChoice`. The shell serializes its HTTP write, then settles that token. Older successful writes advance the latest choice's rollback baseline without settling its overlay. Topic-channel echoes update the baseline while preserving the pending selection. Rejection changes only notification level on the current row. The shell releases a choice when its write tail finishes.

The shell groups notification transaction state into private typed entries. Each topic queue keeps its account lease, latest attempt and finishing tail together. A category account keeps one shared write tail because category responses include account-wide inherited mute lists. Its category queues retain each latest attempt, finishing tail and last confirmed level. Admission installs queue ownership before optimistic Store publication. Retirement removes these entries before retiring the shared reconcilers, so old completions cannot clear replacement-account state. HTTP, current-user preference merging and tracking refresh remain in the shell.

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

Transport retry closures remain shell-owned because they capture credentials and API arguments. `failSnapshot` records retry phase and rejects stale failures. The shell opens the next ticket before admitting its triggering message. This keeps transport concerns outside the reconciler while concentrating load authority inside it.

## Implementation reconciliation

The design panel proposed separate basis classes and one method per load cause. The implementation uses snapshot readiness plus the orthogonal load phase, and one ticket operation for initial, retry, resume, and category reads. This preserves serving a loaded basis during refresh with fewer caller methods. Bootstrap has its own capture token because it may precede HTTP fallback.

The existing partial-report policy and explicit acknowledged mark-unread reset are preserved. This refactor makes no performance claim and adds no notifier. The shell retains active-site notification checks and its microtask coalescing.

## Validation

`topic_tracking_reconciler_test.dart` pins pure delayed report reconciliation, choice settlement, category barriers, admission-time replay, retry, truncation, and retirement. The owning shell notification, muted tracking, async ordering, unread, and rebuild-isolation tests exercise production adapters and publication.
