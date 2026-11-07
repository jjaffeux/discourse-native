# Notification pause ownership

`DoNotDisturbController` keeps one private account owner per captured
`SiteLease`. The owner holds the pause snapshot, write ticket, live revision,
restoration protection, and expiry timer. These values previously occupied
five independently maintained URL collections.

A snapshot distinguishes an unread value from a confirmed inactive pause.
Restoration remains silent, and a failed first write still permits later
restoration unless a newer live update has established authority. Ordinary
snapshots cannot replace a pending write. Live messages advance the account's
revision even when their value is unchanged, so an older write cannot replace
that confirmation.

Retirement removes only the exact owner, cancels its timer, clears its retained
state, and notifies listeners after cleanup. A successor write at the same URL
can begin while old HTTP remains pending. The old dispatched write is not
aborted or treated as undone; its existing future still follows its transport
completion, and it cannot publish into the successor.

Invalidation and commit callbacks can synchronously rotate accounts or publish
newer live state. Publication and cleanup recheck the captured account and write
ticket after callbacks. Live and expiry publication also retain their revision,
so a newer live message delivered by a callback wins. Timer callbacks require
both the captured account and exact timer identity. An earlier retirement
observer may install a successor without old cleanup cancelling its timer.

Minute ticks and exact expiry retain the existing monotonic-timer behavior;
foreground checks still reconcile wall-clock changes and suspended execution.
Expiry from a retired account cannot clear or persist a successor's pause.

Adding cleanup guards to each former collection would preserve the same split
ownership. A private account state owner keeps the existing controller's domain
logic and public API, while making authority and timer lifetime explicit. No
generic scheduler or extra callback protocol is introduced.

Focused controller tests reproduce the prior account-replacement, timer,
cleanup-hook, and live-reentrancy failures. Dialog and user-status expiry suites
exercise the existing shell and presentation contracts.
