# Chat channel directory ownership

`ChatController` remains the facade used by plugins and views. Its private `_ChatChannelDirectory` owns one site and one captured `PluginSiteLease`. The controller registry reuses only a current owner. Account forget detaches that owner before retiring it. Controller disposal detaches every directory before retiring their work.

The directory owns public and direct channel ordering, shared list loading and retry state, detail request identity, partial channel knowledge, the active `ChatChannelRefresh`, and per-channel pending operations. Canonical channels stay in Store. The owner keeps only IDs and transient request state. Existing list preferences and browse filter/page state retain their current UI owners.

Local and live channel mutations go through the directory so an in-flight snapshot records newer fields and accepted tracking. HTTP hydration remains a separate operation. An embedded thread channel is partial until a full detail or snapshot resolves it. The private [thread catalog](chat-thread-catalog.md) owns retained thread-list pagination behind the controller facade. `ChatThreadDirectory` coordinates browsing.

Star and notification projections and rollback rebase only their fields onto the current channel. Metadata and status share a settings lock with separate live-echo flags. Full serializer replies contribute only the submitted settings. Read cursors, tracking, unrelated settings, and conflicting live edits survive delayed replies. Unmuting obtains fresh detail cursors before the existing live coordinator resumes messages.

Retiring a directory disowns list/detail/resume work and channel writes together. A later account gets a new owner, so old response cleanup cannot finish its requests or undo its optimistic fields. The plugin lease exposes `isCurrent` and `commit`; it has no retirement callback. Every asynchronous boundary therefore checks the captured lease and the owner lifetime. Lookup replaces stale owners.

`ChatLiveSyncCoordinator` continues to own subscriptions and view claims. `ChatSendCoordinator` continues to own outgoing reconciliation. `_ChatConversationStream` continues to own retained windows, Store pins, notices and receipt owner lifetimes. Directory replacement does not retire retained conversations. Channel revocation asks the directory to remove its listing/detail/resume state, then the controller performs the existing thread and conversation revocation policy.

The chosen private part keeps the implementation behind the established facade and uses the existing concrete live coordinator. An importable directory with a new activity interface was viable but added another public API for one collaborator. Both designs keep directory reads and writes together because they share refresh reconciliation and notification contribution policy.

`chat_channel_directory_lifetime_test.dart` pins retirement, replacement, old cleanup, credential waits and retained conversation identity through the facade. Controller and settings response tests pin field reconciliation. Directory widget tests exercise mounted service replacement and can save rendered evidence through `NATIVE_UI_EVIDENCE_DIR`.

## Retained member lists

`ChatChannelMembersSession` captures an account lease in its channel target.
The target owns a detachable retirement observation, independently of the
controller's guarded HTTP fetch. Retirement immediately clears retained members,
request/error/cursor state and pending search debounce. A controller, site,
channel and membership count can remain equal across an account change; binding
also requires the held account lease to remain current.

Explicit refresh or binding may acquire a successor account lease. Old responses
and old retirement callbacks cannot settle or clear that successor's query.
Rebinding and disposal detach the old target's observation. Pagination, member
ID deduplication and committed search behavior retain their existing policy.
The mounted view supplies identifiers and listens to the session; it does not
own account retirement or add another lifecycle listener.

Member-session tests cover immediate retirement, equal-target successor binding,
late success/failure and a prior retirement observer that binds the successor.
Existing directory and channel-info tests cover account HTTP admission and UI use.

## Retained browse directories

`ChatBrowseSession` also owns an account lease for its retained directory rows.
Account retirement clears rows, server cursor, pending request/error state and
search debounce immediately. The mounted document keeps its filter choices;
explicit refresh captures a successor lease and starts at offset zero. Automatic
prefetch cannot reopen a retired account or borrow its cursor.

Every browse request captures its account owner as well as its immutable query.
Both dispatch and settlement require that exact owner, current lease and request.
An older retirement callback or late response cannot clear a successor request.
Successor admission also clears outgoing rows before notifying listeners, even
when another retirement observer refreshes before this session's callback runs.
Refresh and disposal detach the previous account observation. Disposal from a
synchronous retirement listener waits until notifier dispatch has unwound.
No widget lifecycle listener or general request dispatcher is added.

Browse-session tests use the real controller and request host to reproduce old
retained rows after invalidation, and cover late success/failure, a prior
retirement observer refreshing the successor, and reentrant disposal. Existing
view, parity and scroll tests retain filtering and pagination coverage.
