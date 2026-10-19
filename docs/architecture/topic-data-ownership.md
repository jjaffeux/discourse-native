# Topic data ownership

`TopicDataOwner` owns incoming topic and post data. Shell navigation chooses a
route and a tab window. The owner fetches, reconciles and publishes canonical
records through `Store`.

## Account lifetime

The shell owns one directory. `forSite(siteUrl)` returns a `TopicDataSession`
bound to the current `SiteLease`. The session never resolves itself through the
directory again. It captures request credentials through `AccountRequestSession`
and checks the original lease after asynchronous work and before each observable
publication.

Use `forLease(siteUrl, originalLease)` for a continuation of existing work.
A retired continuation must not obtain a session for a successor account at the
same URL. Store and shell listeners can retire a session synchronously, so a
single check before a multi-record publication is insufficient.

Account retirement discards operation metadata and speculative reads. Old
cleanup cannot remove the successor's loading state or post holds. A session
contains operation state, summary IDs and removal history. It does not cache
another copy of canonical entities.

## Ownership boundaries

| Owner | Responsibility |
| --- | --- |
| `TopicDataSession` | Open, refresh, ID paging, mega paging, gap expansion, summary, jump hydration, live invalidation, after-write repair and ambiguous-write lookup publication. |
| `Store` and model merge methods | Canonical `Post`, `TopicDetail` and list-row records, record merge and retention. |
| `ShellTabContext` and shell navigation | Route targets, ordinary-topic loaded windows, saved scroll anchors, highlights and originating-tab presentation. |
| `TopicReadController` | Read observations, timing requests and read-position lifecycle. |
| `TopicTrackingReconciler` | Tracking snapshots, unread/read precedence and row projection. |
| Feature mutation adapters | Request validation, mutation endpoints, typed write outcomes, title/category/tag/status projections, folder policy and route changes. |
| Composer and draft owners | Editing invariants, submission state, draft sequence proof, settlement and composer lifetime. |

`TopicOpening` supplies presentation hooks for the originating tab's message-list
parent and eligible resume position. The data owner decides cache admission,
request sharing, replay and dispatch freshness. Category enrichment is an
injected operation within the original opening deadline.

## Read admission

A topic shares one full read. A force request during that read queues a refresh.
An explicit queued position takes precedence over an unpositioned server resume.
Queued refresh remains pending through settlement notifications. A successor
open inherits its forced-read requirement and consumes it only when reserving a
fresh read. Cached navigation and speculative results cannot erase that work.
Ordinary resume remains awaited by the initial open; a queued replay runs in the
background. Prefetch adoption retains the dispatch stamp from the speculative
request.

ID pages hydrate only absent posts, preserving held posts during and after a
write. A missing ID can leave the stream only when no newer committed full
stream or active full reconciliation protects membership. Mega pages and gaps
keep their own publication policies. Summary reads publish summary posts and
IDs without replacing the full detail or advancing full-stream authority.
Recommendations fill an unresolved snapshot only. An empty resolved snapshot
remains resolved.

Each read captures bookmark authority from `BookmarkReadProjection`, plus its
archive, removal and stream revisions. Publication preserves fields written
after dispatch. Removal history filters only removals
newer than the read, allowing a later response to recover a post. Publication
rechecks these revisions between observable Store writes.

## Writes and live updates

`beginPostWrite` admits an exclusive write and returns an identity-owned release
closure. `holdPostWrite` allows overlapping holds for existing bookmark and bulk
operations. Releases are idempotent. The final release replays one deferred live
invalidation. The existing plugin begin/end API adapts to the same accounting.

Live invalidation batches at most 20 post IDs per request and admits each post
against its own current owner. Deletion totals wait for the corresponding post
refreshes. A newer invalidation or write hold prevents an older batch from
publishing that post.

Accepted post edits, actions, checklist changes, replies and archive changes
use semantic topic session methods.
[BookmarkTransactions](bookmark-transactions.md) owns bookmark operations,
revisions and field projections. The topic session supplies nonpublishing
bookmark metadata reads and shared post holds through `BookmarkTopicData`.
Post moderation uses [typed outcomes](post-mutation-outcomes.md) and read-only
uncertainty recovery. Presentation consumers own its localization. A repair after an accepted mutation uses the original lease and captured key. Selected-post repair collects every batch
before publishing any result. A failed later batch therefore cannot expose a
partial repair.

Ambiguous reply and new-topic lookup perform their incoming reads in the
session. The composer still decides the submission outcome and draft settlement.
Only a unique matching created topic is published.

## Verification

`topic_data_owner_test.dart` exercises account retirement, synchronous Store
listener retirement, resume replay and full-stream authority. The shell tests
`topic_data_tab_windows_test.dart` and `topic_data_reply_completion_test.dart`
cover independent inactive-tab windows and retirement during accepted-reply
notification. Existing ordering, selected repair, bookmark, archive, prefetch,
summary, composer and reader suites pin the migrated behavior.
