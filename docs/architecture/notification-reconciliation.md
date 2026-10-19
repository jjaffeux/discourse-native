# Notification reconciliation

`NotificationReconciliation` owns effective notification rows and count authority
for one `SiteLease`. `AccountActivityController` retains transport, credentials,
request coalescing, diagnostics, refresh sequencing, and persistence callbacks.
Its existing public API and plugin hosts continue to use the same feeds.

## Feed registration

`NotificationFeedSlot.notifications` and `NotificationFeedSlot.reminders` bind a
snapshot type to its aspect callback. The owner stores each published
`NotificationFeed` or whole `BookmarkFeed`. Private adapters traverse notification
rows and reminder rows through their existing `withRead` and `withUnread`
transforms. Registering another slot includes it in read propagation, rollback,
and dismissal coverage without another controller branch.

Snapshots retain ordering, loading state, errors, duplicate occurrences, and
feed-specific wire metadata. There is no canonical row chosen between feeds
that contain the same notification ID. Local read pins overlay every incoming
snapshot, including bookmark reminders.

## Read and dismissal tickets

`beginRead` captures row authority, prior pin state, and grouped authority. It
pins the row and decrements an available grouped bucket. `failRead` restores the
row only if this attempt introduced its pin and no successful dismissal covered
that ID. Count rollback independently requires unchanged snapshot and type
authority. `confirmRead` advances the existing current-user authority callback.

`beginDismiss` freezes cached IDs before the network write, including rows
already marked read by a pending click. A plugin source's server filter also
covers rows missing type metadata. Other feeds match declared names or numeric
IDs. `confirmDismiss` pins only the frozen IDs and advances their row authority.
It clears affected buckets only if no newer grouped authority won. Rows first
received during the write remain outside its coverage.

Both write types advance the current-user callback before the request and after
success, including when grouped buckets are absent or zero. That callback keeps
the existing `CurrentUserReconciler` boundary separate from local rollback.

## Count authority

Rows, complete grouped snapshots, affected types, totals fields, and plugin
counters have independent revisions. Totals tickets capture the before value
and field revisions. Acceptance uses `NotificationTotals.mergeRefresh` to retain
newer fields while accepting unrelated response fields.

An available equal grouped confirmation advances snapshot authority. An omitted
grouped map grants no authority. Local decrement and rollback advance the totals
field revision while preserving their separate rollback token. Plugin counters
and aggregate live confirmations advance independently, even for equal values.

## Publication and lifetime

Each mutation commits all snapshots and totals before callbacks run. Reentrant
publications queue another callback batch. Dispatch stops if an aspect callback
retires the owner or its account lease. The controller rechecks request ownership
before post-load effects and follow-up requests.

Tickets have private constructors and belong to their issuing owner. Foreign,
settled, retired, and replaced-account tickets cannot mutate a successor. Owner
lookup replaces stale lease sessions even when the site URL is reused. Account
forgetting clears the owner before notifying the affected aspects.

`notification_reconciliation_test.dart` covers synthetic feed registration,
reminders, metadata, frozen coverage, confirmations, ticket lifetime, and
reentrant publication. Existing account activity and notification tests exercise
the production loaders and network completion orderings.
