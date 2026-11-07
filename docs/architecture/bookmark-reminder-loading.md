# Bookmark reminder loading

`AccountActivityController.loadBookmarks` loads the user menu's reminder and
bookmark snapshot. This is separate from the paged bookmarks page owned by
`BookmarkListOwner` and from bookmark write transactions.

A private `_AccountBookmarkRefresh` owns one captured account lease, its active
job, and at most one forced replay. Ordinary overlapping loads share the active
completion. Forced loads share a pending completion and retain the latest
instance for its username. A force during replay queues another replay. The
active job is registered before loading publication, so synchronous listeners
join it rather than dispatch duplicate work.

Retiring the lease, forgetting the site, or disposing the controller detaches
the owner, releases both active and pending callers, and drops queued work.
Cleanup removes only the exact owner from its map, independently of publication
authority. A successor account at the same URL does not join retired HTTP or
inherit a stale request token. Physical completion or failure from a retired
request cannot publish, clear a successor, or start an old replay.

`NotificationReconciliation` still owns feed snapshots and read overlays. The
loader retains rows on refresh errors, the existing loading and reconnect
messages, key-only credential acquisition, and the account request scope. A
loading listener that retires the account prevents subsequent credential IO.

The private per-account owner replaces five coordinated URL maps. A smaller
cleanup-only patch would still need to synchronize task identity, account
identity, pending instances, and two kinds of waiters. These values instead
share one lifetime; no common framework is added for totals, paged history,
or notification feeds with different replay policies.

`test/account_activity_controller_test.dart` covers response orders across
account replacement, retired errors and forced waiters, shared replay, the
latest replay username, forces during replay, and synchronous rotation from
loading and publication. Existing read and dismissal tests continue to exercise
the same reconciliation path.
