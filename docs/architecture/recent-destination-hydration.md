# Recent destination hydration

`RecentDestinationsStore` owns the published account-scoped visit lists and
acceptance of persisted history. `ShellController` starts its load alongside
other startup reads. `AppRuntime` retains the store when replacing shell
controllers, so startup and synchronous navigation or removal can overlap.
The snapshot writer orders physical storage operations; it does not decide
whether an older read may replace a newer local interaction.

One private hydration owner coalesces overlapping reads. It records visits
accepted after reading begins, keeping the same five-entry limit for each
account and category/channel/topic list. Both live recording and replay use the
same ordering, destination identity, metadata replacement, and deduplication
routine. A successful read is decoded into a private map; removal exclusions
and staged visits are applied before that map replaces the published state.
Untouched saved history remains available beside newer visits.

Forgetting a forum excludes all its stored accounts, even when the pending
read has not exposed them yet. Retaining forums narrows the allowed stored
sites cumulatively. Both operations also remove earlier staged visits in their
scope. A later explicit visit can add the forum again without reviving its
excluded saved history. Supplied retain sets are copied, not retained by
reference.

Mutators return whether visible history or pending history changed and needs
saving. Thus forgetting or retaining while a read is pending can return true
without currently visible rows; existing shell callers then request the
necessary save. An absent forum still returns false once hydration is complete.
Saving during hydration waits for the merge and serializes its resulting
canonical map, rather than persisting a partial new-visit-only document. The
load never automatically writes history.

A failed storage read keeps published visits, staged interactions, and removal
exclusions for a later retry. Saving remains blocked until storage is readable.
Malformed optional history keeps the existing empty-base recovery policy while
retaining interactions accepted during that read. Completed reads release their
pending completion, and a later explicit load can read storage again.

Skipping every read after any mutation would discard unrelated saved history.
Making all mutations asynchronous would change navigation callers and still
need ordering policy. The bounded hydration journal keeps the synchronous API
and one publication owner without a generic transaction framework.

`DestinationBookmarksStore` retains a different durability contract: its
mutation transactions reject while loading and publish only after a successful
write. It does not use this optional-history merge policy.

Focused recent-store tests cover delayed visits, caller-requested saves,
forget/retain exclusions, removal ordering, coalesced reads, malformed history,
and read failure followed by successful retry. Six new hydration cases failed
against the previous unconditional replacement behavior.
