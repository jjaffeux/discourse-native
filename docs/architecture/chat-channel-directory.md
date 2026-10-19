# Chat channel directory ownership

`ChatController` remains the facade used by plugins and views. Its private `_ChatChannelDirectory` owns one site and one captured `PluginSiteLease`. The controller registry reuses only a current owner. Account forget detaches that owner before retiring it. Controller disposal detaches every directory before retiring their work.

The directory owns public and direct channel ordering, shared list loading and retry state, detail request identity, partial channel knowledge, the active `ChatChannelRefresh`, and per-channel pending operations. Canonical channels stay in Store. The owner keeps only IDs and transient request state. Existing list preferences and browse filter/page state retain their current UI owners.

Local and live channel mutations go through the directory so an in-flight snapshot records newer fields and accepted tracking. HTTP hydration remains a separate operation. An embedded thread channel is partial until a full detail or snapshot resolves it. The private [thread catalog](chat-thread-catalog.md) owns retained thread-list pagination behind the controller facade. `ChatThreadDirectory` coordinates browsing.

Star and notification projections and rollback rebase only their fields onto the current channel. Metadata and status share a settings lock with separate live-echo flags. Full serializer replies contribute only the submitted settings. Read cursors, tracking, unrelated settings, and conflicting live edits survive delayed replies. Unmuting obtains fresh detail cursors before the existing live coordinator resumes messages.

Retiring a directory disowns list/detail/resume work and channel writes together. A later account gets a new owner, so old response cleanup cannot finish its requests or undo its optimistic fields. The plugin lease exposes `isCurrent` and `commit`; it has no retirement callback. Every asynchronous boundary therefore checks the captured lease and the owner lifetime. Lookup replaces stale owners.

`ChatLiveSyncCoordinator` continues to own subscriptions and view claims. `ChatSendCoordinator` continues to own outgoing reconciliation. `_ChatConversationStream` continues to own retained windows, Store pins, notices and read drains. Directory replacement does not retire retained conversations. Channel revocation asks the directory to remove its listing/detail/resume state, then the controller performs the existing thread and conversation revocation policy.

The chosen private part keeps the implementation behind the established facade and uses the existing concrete live coordinator. An importable directory with a new activity interface was viable but added another public API for one collaborator. Both designs keep directory reads and writes together because they share refresh reconciliation and notification contribution policy.

`chat_channel_directory_lifetime_test.dart` pins retirement, replacement, old cleanup, credential waits and retained conversation identity through the facade. Controller and settings response tests pin field reconciliation. Directory widget tests exercise mounted service replacement and can save rendered evidence through `NATIVE_UI_EVIDENCE_DIR`.
