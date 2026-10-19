# Custom sidebar transactions

`CustomSidebarSections` owns server sections and their account-scoped loading,
retry, live invalidation, reorder, and cross-section move transactions.
`ShellController` supplies current instance and selection lookups, wires the
MessageBus channel, and exposes the existing sidebar queries and actions.
`SidebarSectionStore` continues to own persisted collapse choices. Native
sidebar components own drag previews, public-edit confirmation, and errors.

Each private account record captures a `SiteLease`. Credential acquisition and
HTTP run through `AccountRequestSession` under that lease. Anonymous reads use
its explicit anonymous capability and never read private credentials or a client
ID. Publication and cleanup check both the lease and the captured account
record. Forgetting a record also rejects old work when the lifecycle generation
stays the same. Old finalizers cannot clear a successor's requests or locks.

Only the selected readable site starts a load. Selection is checked again after
credential acquisition. A request already dispatched can populate the account's
cache after switching away. Successful empty results count as loaded. Failed
HTTP attempts suppress retries for five minutes; credential failures do not
start that interval. Live invalidation clears the interval and preserves the
visible snapshot while requesting a replacement.

Reorder reserves one remote section ID. Move reserves both IDs atomically.
Permissions, source membership, indices, and target capacity are checked before
reservation and again after credential acquisition. Public sections require an
admin. Writes use the existing server endpoints and publish confirmed results,
with both moved sections replaced in one notification. Actual write failures
propagate to the UI and release the reservations. No write is retried
automatically, including writes with an unknown server outcome.

A local write supersedes older full-list loads. Full-list reads wait until the
last pending write releases its sections. Separate section writes merge their
responses into the latest list, preserving both results. A live announcement
advances a separate version, so a write started before it cannot publish over
the newer server state. Such announcements coalesce into one refresh after the
pending writes settle. An inactive site retains the need to reload until its
next selection.

`ensure` joins a load it can admit. When loading is suppressed or deferred, its
future completes immediately. Completion does not promise a fresh snapshot or
follow a later superseding request. Notifications publish the actual changes.
The owner freezes section and destination lists and caches the composed sidebar
by instance and custom-list identity.

The design compared private account records with an immutable reducer and
effect runner. Private records keep asynchronous policy in one concrete owner
with fewer types. Separate read and live versions express the two ordering
rules without discarding unrelated successful writes. Focused owner tests pin
these races; existing sidebar tests retain desktop and mobile gesture,
confirmation, sign-out, persistence, and startup request contracts.
