# Current-user snapshot precedence

`DiscourseInstance.user` remains the authoritative current-user record.
`CurrentUserReconciler` owns the precedence between a full server snapshot and
newer local or live fields for one account lease. It stores revisions and plugin
option transformations, without retaining a user or publishing changes.

## Caller usage

```dart
final owner = CurrentUserReconciler(lease: lease, models: models);
final ticket = owner.beginSnapshot();
final response = await request.run(loadCurrentUser);
lease.commit(() {
  final result = owner.reconcile(
    ticket,
    previous: instance.user,
    incoming: response,
  );
  if (result == null) return;
  publish(result.user);
});
```

Bootstrap and session reads capture an opaque `CurrentUserSnapshot` before
their asynchronous work. The shell supplies its latest user at acceptance and
keeps its existing request capabilities. A ticket belongs to its issuing owner;
retiring the owner or its lease prevents acceptance, including when a successor
has identical revision values.

## Authority and publication

Presence writes advance authority at both start and settlement. A snapshot
dispatched during a pending write also preserves the confirmed presence value.
Grouped unread authority advances on accepted complete live maps and local
notification read or dismiss operations. Draft authority advances on every
valid live count, including repeated values. Successful category writes advance
category authority. Confirmed plugin option updates record the latest
transformation for each field before applying it, including equal updates.

Full reconciliation preserves those newer fields for the same account while
accepting unrelated response fields. The existing model codec decides account
identity and preserves unknown plugin namespaces. Plugin transformations newer
than dispatch replay over the response's plugin data. A discovered account
change clears those transformations but keeps revisions monotonic until
retirement, because other reads may still carry earlier revisions.

The result contains the reconciled user, whether its account changed, and
whether grouped counts may seed account totals. A stale grouped snapshot can
refresh other user fields but cannot reseed totals. The shell retains account
cache resets, instance replacement, persistence, notification and plugin
observer dispatch. DND retains its existing owner and pre-merge acceptance.
Concurrent full responses retain their existing acceptance order.

## Category-only reads

Bootstrap checks `categoryPreferencesAreCurrent` before installing the
accompanying tracking report, including when it has no current-user payload.
A successful category write captures a new ticket for its follow-up read.
`acceptsCategoryPreferences` requires an unchanged category revision and the
same account. The existing selective commit helper applies only non-null
category lists to the latest user. That read cannot replace unrelated fields.

## Design choice and proof

The design compared a single account-bound owner with a site-wide set of typed
precedence lanes. The independent comparison preferred the account-bound owner
and the selective category boundary. Model the Domain concentrates ticket and
field precedence in one module. Laziness Protocol keeps the API small and
leaves canonical storage and effects with their existing owners. Another user
cache, an event log, and synthetic account generations would add ownership or
change response ordering without helping this extraction.

`current_user_reconciler_test.dart` pins ticket lifetime, independent field
authority, plugin overlays, account transitions, and grouped seed eligibility.
The owning presence, notification, category, bootstrap, and Chat session tests
exercise the production adapters and persistence. This refactor changes no UI
or persistence schema and makes no performance claim.
