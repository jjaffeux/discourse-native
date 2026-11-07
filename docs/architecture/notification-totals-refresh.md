# Notification totals refresh

`AccountActivityController.refresh(instance, force: ...)` remains the shell's
entry point. A private `_AccountTotalsRefresh` owns totals transport and request
sequencing for one captured `SiteLease`. The controller holds one map of these
owners. `NotificationReconciliation` remains the authority for merging live and
HTTP counts; the refresh owner captures its ticket before credential IO.

Ordinary overlapping callers share the active completion. Forced callers share
one pending replay, with the latest requested instance. Starting a request sets
the account's attempt timestamp; ordinary callers reuse reconciled totals during
the cooldown, while forced callers bypass it. Replay starts before the preceding
caller's completion is delivered.

Lifecycle retirement detaches the owner, removes it only if it still occupies
its map entry, and completes active and pending callers with null. Neither a
blocked credential read nor delayed HTTP can delay a replacement account. The
replacement has its own cooldown. `forget` and controller disposal retire owners
through the same path, and late completions cannot remove successor work.

Count publication can synchronously retire the account through a listener. Once
publication has begun, the active caller receives the result accepted by its
reconciliation ticket, preserving the existing completion contract. Retirement
still suppresses the post-load account callback and cancels pending replay.
Outside this synchronous publication interval, retired callers complete null.
Ownership is checked again after publication before the callback.

The private Dart part keeps lifetime state alongside the controller without
exposing another public API or distributing sequencing across parallel URL maps.
An alternative standalone owner would require forwarding reconciliation and
presentation callbacks without another independent consumer. No general request
framework is introduced.

Focused verification lives in `test/account_activity_controller_test.dart` and
`test/account_activity_totals_integration_test.dart`: coalescing, replay, live
count authority, rate limiting, retirement without explicit cleanup, replacement
work before old HTTP settles, and synchronous account rotation during publication.
