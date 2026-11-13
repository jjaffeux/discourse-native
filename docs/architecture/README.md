# Application ownership

Start here when deciding where a change belongs. The shell composes owners and
adapts navigation and presentation; feature state, request lifetime, and write
reconciliation belong to the owners below. Each linked contract describes the
behavior its focused tests protect.

## Choose an owner

| Responsibility | Owning code | Contracts |
| --- | --- | --- |
| Construct, replace and dispose application services | `AppRuntime`, `ShellController` | [Runtime replacement](runtime-replacement.md), [shutdown errors](account-retirement-errors.md) |
| Retire an account and scope its HTTP work | `SiteLifecycle`, `AccountSessionCoordinator`, `AccountRequestSession` | [Account requests](account-request-sessions.md), [read sessions](account-read-sessions.md) |
| Implement HTTP behavior and domain endpoints | `DiscourseTransport`, independent domain API libraries | [Domain libraries](api-domain-libraries.md), [plugin transport](plugin-http-transport.md), [client identity](http-client-identity.md) |
| Install plugin contributions and close a session | `InstalledPlugins`, `PluginSession` | [Session teardown](plugin-session-retirement.md) |
| Reconcile topic entities and accepted mutations | `TopicDataSession`, action owners, `TopicReadController` | [Topic data and read progress](topic-data-ownership.md), [post outcomes](post-mutation-outcomes.md), [bookmarks](bookmark-transactions.md) |
| Reconcile current-user snapshots and confirmed preferences | `CurrentUserReconciler`, preference and profile owners | [Current user](current-user-reconciliation.md), [profile writes](profile-write-transactions.md) |
| Retain notification totals, feeds, and read authority | `AccountActivityController` and its private account/request owners | [Reconciliation](notification-reconciliation.md), [totals](notification-totals-refresh.md), [feed loading](notification-feed-loading.md), [reminders](bookmark-reminder-loading.md), [pause](notification-pause-ownership.md) |
| Deliver external notification navigation | `AppRuntime` notification ingress | [Destination lifetime](notification-ingress-lifetime.md) |
| Retain global search documents, account results and recent history | `GlobalSearchController`, `RecentSearchHistory`, plugin search owners | [Core search lifetime](core-global-search-lifetime.md), [Chat search lifetime](chat-global-search-lifetime.md) |
| Track what stands between the user and a forum, and what each forum allows | `ForumAccessState`, `SiteCapabilities` | [Round eleven](layer-dependencies-round11.md) |
| Retain appearance, emoji catalogs, and cooking inputs | `SitePresentationController`, `CookingContextOwner` | [Presentation sessions](presentation-sessions.md), [cooked rendering](../cooked-rendering.md) |
| Retain composers, prepare openings, and coordinate saves | Composer opening owners, registry, controller, draft coordinator | [Composer architecture](../composer-architecture.md), [draft accounts](draft-account-ownership.md) |
| Persist workspaces, recent visits, and local choices | Their dedicated stores and write queues | [Workspace snapshots](workspace-storage-snapshots.md), [recent hydration](recent-destination-hydration.md), [choice acceptance](presentation-preference-acceptance.md), [welcome claims](welcome-claim-ownership.md) |
| Retain reader geometry, cursor, and tracking state | Topic viewport, cursor, and tracking owners | [Geometry](keyed-reader-geometry.md), [cursor](topic-list-cursor.md), [tracking](topic-tracking-reconciliation.md), [tab context](tab-presentation-context.md) |
| Own optional feature data and behavior | The feature's plugin module, using public SDK contracts | [Chat directory](chat-channel-directory.md), [Chat streams](chat-conversation-streams.md), [thread catalog](chat-thread-catalog.md), [voice lifetime](voice-call-lifetime.md), [assigned group queries](assigned-group-queries.md), [board accounts](boards-account-lifetime.md) |

## Keep identity with the state it governs

An account session is more precise than a site URL. Retained account state uses
its captured lease for request and write authority; a new account at the same
URL must receive its own authority and request admission. Keep a request token
or completion beside the state it protects, rather than maintaining matching
entries in several maps.

Retire the exact account or request authority before publishing a change.
Document handles, documented display fallbacks and accepted projections can
remain readable according to the feature's contract; they do not establish
current account permissions or freshness. A callback may synchronously admit a
successor. Late success, failure, or cleanup from the old owner must not erase
or settle the successor's request. A caller's future
may still wait for physical I/O where that is the documented contract; losing
publication authority and completing transport work are separate events.

Deferred UI cleanup keeps its issuing account configuration. Completing an old
search surface cannot clear a successor's query or filters; a synchronous
publication between cleanup steps requires the same ownership check.

Distinguish passive cache queries from explicit resource admission. Passive
getters read cached values or documented fallbacks without starting requests.
Acquiring a ref or handle, or an explicit consumer load or refresh, may admit an
owner; the feature's contract determines when network work starts.

For accepted writes, preserve field authority against older reads. Confirmed
state can differ from a pending draft or optimistic projection. Reuse the
feature's reconciliation owner instead of adding another shell-level revision
or duplicating parsing in a widget.

## Keep boundaries narrow

Domain API libraries borrow the HTTP transport; they do not share private
implementation through Dart `part` declarations. Transport policy stays in the
transport, and domain endpoint and payload knowledge stays in its API library.
Optional plugin endpoints and wire parsing stay in their plugin module. Core
provides generic HTTP and SDK contracts and shared presentation.

Standalone feature owners receive the capabilities they use. They do not
import `ShellController` through another helper to regain all shell authority.
Widgets render their state and dispatch intent. Existing ownership-boundary
tests check these dependencies transitively.

Persistence policy is specific to the operation. Some mutations publish only
after durability; some accept an optimistic choice and expose save status.
Use the store's existing owner/key queue and documented read barrier. Do not
introduce a second queue, assume every load can overwrite live choices, or
change a persistence failure into a successful empty document.

## Verify a changed contract

Run explicit test files for the owner and its directly affected callers. Useful
cross-cutting checks include `owner_dependency_graph_test.dart`,
`standalone_owner_dependency_boundary_test.dart`,
`plugin_dependency_boundary_test.dart`, `site_preference_inventory_test.dart`,
and `architecture_layer_contract_test.dart` when their boundaries change. Follow the repository's focused-test rule in
`AGENTS.md`; CI runs the full suite.

Concurrency tests should hold the relevant boundary with a completer and
observe public state or calls: retire during credentials or HTTP, admit a
successor before the old request completes, complete old success and failure,
and reenter during publication when the owner permits callbacks. Keep the
resulting contract with its owner so future changes can distinguish intentional
behavior from incidental sequencing.

## Verified refinements

[Ten verified ownership improvements](verified-owner-improvements.md) records
the storage, request identity, and media scheduling changes, with before/after
behavior and focused commands to reproduce their proof.

[Runtime state integrity](runtime-state-integrity.md) records ten further
improvements to replacement-store transactions, shared preference documents,
request retirement, cache admission, recovery, and immutable publication.

[Layer dependencies](layer-dependencies-round6.md) records how the import graph
went from one 721-library cycle to a one-way layer order, with the measurements
and the remaining limits.

[Round nine](layer-dependencies-round9.md) records ten improvements with a
rerunnable proof each, and the proof manifest to rerun them.

[Round eleven](layer-dependencies-round11.md) records ten reductions in
dependency reach across data, plugins, and the shell.

[Round twelve](layer-dependencies-round12.md) records ten more dependency
reductions and the import graph and behavior checks for each.
