# Draft list account ownership

`DraftListController` keeps a private `_DraftAccount` for each site's captured
`SiteLease`. The owner holds the feed, active page ticket, queued refresh,
deletion tickets and deletion tombstones. Cached getters require a current
owner. Lifecycle retirement removes only that owner, detaches its observer and
clears its state and notifies listeners so mounted lists can request the replacement
account; explicit forgetting and disposal use the same retirement path.

Page and deletion operations capture their owner before publishing loading state
or reading credentials. A replacement account can dispatch immediately while old
HTTP is still pending. Old completions cannot publish, clear successor tickets,
carry deletion tombstones into a successor page, or replay a retired refresh.
Retirement does not abort a dispatched deletion or claim its server effects were
undone. The old operation's future retains its existing physical completion
semantics; duplicate loads and queued refresh calls still return immediately.

The controller retains paging and mutation orchestration. Refresh retains visible
rows until page one replaces them. Tombstones outrank overlapping page responses;
existing cursor correction, previous-page fallback refresh and externally
reported draft deletion remain unchanged. A queued refresh keeps the latest
instance within its original account owner.

A behavioral repository with load/delete callbacks would add forwarding without
a second consumer. A private state collaborator instead unifies the five former
URL maps under their actual account lifetime while keeping domain logic local.

This is ownership hardening. Shell cleanup already pairs lifecycle invalidation
with explicit draft forgetting, so these changes do not demonstrate a reachable
production account leak. The controller now upholds its own account boundary
without depending on that paired call order.

`test/draft_list_controller_test.dart` covers retirement without forgetting,
replacement before old HTTP settles, late errors, deletion-key isolation,
tombstone/cursor isolation, refresh replay, pagination and deletion during loads.
The draft list and recovery widget tests cover the unchanged presentation and
recovery facade.
