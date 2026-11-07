# Core global search account lifetime

`GlobalSearchController` owns one configured search document. Its captured site
lease governs retained results, filter choices, conditions, query, capabilities,
lookups, and execution. Per-request checks alone cannot withdraw a result that
already finished before the account retired.

The configuration observes account retirement before configuring recent
history. Retirement clears the document and execution, withdraws account-derived
capabilities, and leaves the controller unconfigured. Normal shell site syncing
or an explicit `configure` admits the next account with its current capabilities;
the old query is not automatically replayed. Durable recent-search storage is
not deleted by this in-memory withdrawal.

Configuration clears old account state and sanitizes conditions against current
capabilities before publishing recent-history changes.
A listener can configure a successor or submit a search during that publication.
The outer configuration checks its revision before continuing, and preserves an
execution already admitted by a listener, including immediate submission rather
than replacing it with debounce. The old recent-history retirement callback also
checks its captured session before clearing state, since retirement fanout may
already have captured that callback before it was detached.

Execution reset aborts old attempts and clears their queued dispatch. Physical
operations that ignore cancellation can still finish, but existing run, attempt,
and lease checks prevent them from publishing into the successor. A new lease
also receives independent in-flight admission slots. Configuration observers are
detached on replacement and disposal.

Focused regression coverage includes completed private result withdrawal before
notification, reentrant successor configuration and recent history, late old
append success and failure, and preserving a submission admitted by a history
listener. Direct integration suites cover controller cancellation, history,
forum scope replacement, and the search UI.

## Result activation

A row may remain painted after its account's results have been withdrawn.
`GlobalSearchController.ownsResult` requires the exact result object to belong
to the current live account configuration. Both navigation admission and click
recording use that check; an old row cannot acquire a successor account's lease
merely because the forum and widget are still present.

Selection analytics capture their site, lease, configuration and logging policy
before remembering the selection. History publication can synchronously
reconfigure the controller. In that case the click is not sent with the next
account's credentials. Once navigation is admitted, `SearchResultActivation`
continues to own its existing route and account checks across asynchronous work.
