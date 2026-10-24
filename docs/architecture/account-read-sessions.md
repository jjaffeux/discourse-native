# Account read ownership

`UserDirectoryController`, `UserSummaryController`, and `BadgesController` keep
one private owner per site and account lease. Their public load, state, forget,
and notifier APIs remain unchanged. Widgets continue listening to each controller
separately from `ShellController`.

## Account boundary

`SiteLifecycle` remains authoritative for account identity. Each owner captures a
`SiteLease`; its stable `session` identity changes when the lifecycle invalidates
the site. Cached getters require that lease to remain current, including when a
caller omits `controller.forget` after invalidation. A changed instance object
alone does not rotate the account session.

The owner subscribes to retirement. Retirement removes only that same owner from
the controller and clears its retained data. Explicit `forget` and controller
disposal detach the subscription. An asynchronous operation captures its owner
and request ticket before reading credentials. Completion checks both the lease
and current owner identity. Its final cleanup touches only captured owner state,
so an old operation cannot release a replacement account's request.

## Data shape

The directory owner holds query states and tickets keyed by `UserDirectoryQuery`,
one shared metadata value and pending metadata future, and a column-update ticket.
Its 16-query bound retains the existing recency behavior. Eviction removes the
query ticket together with its rows. Updating columns clears that owner's queries
and metadata before reloading the selected query. Retirement during publication
prevents the old update from starting a follow-up load.

The summary owner holds one summary state and request ticket. The badge owner
holds states and tickets keyed by `BadgeRoute`, with the existing 16-route bound.
Anonymous directory and badge reads still use anonymous credentials under a
lease. Retirement does not require private credentials to exist.

## Design decision

Model the Domain puts account state and tickets in the same owner. The Laziness
Protocol keeps orchestration in the existing controllers. Moving API operations
into behavioral owners would require dependency and notifier forwarding without
improving isolation. A generic cache framework would obscure the directory's
shared metadata and column invalidation rules.

This is ownership hardening. The former shell cleanup already paired lifecycle
invalidation and forgetting, so this change does not establish a reachable
production account leak or a performance improvement.

Focused controller tests pin cached-read retirement without forgetting, stale
success and failure cleanup, metadata sharing, column-update replacement,
eviction, anonymous reads, paging, and refresh retention. Navigation and rebuild
isolation tests cover the unchanged facade boundary.
