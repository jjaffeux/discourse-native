# Boards account authority

Boards may expose public content, but each loaded snapshot also carries the
viewer's write/manage permissions. `BoardsController` therefore observes one
captured account lease per forum. Its directory, topic-eligible choices, pending
reads, composer receipts and handle snapshots cannot supply authority after that
lease retires. Snapshot and cache getters also check the account before returning
held values, including when an earlier retirement observer runs first.

A board handle remains a document resource identified by forum and board ID.
Account retirement preserves mounted references and the bounded released-handle
registry, while clearing their account data and active read/write tokens. Every
handle's state is cleared before subscriptions are canceled or listeners are
notified. A listener may explicitly refresh under a successor account without a
later old reset erasing that request. Retirement itself does not fetch a new
account or subscribe on its behalf.

Acquire, directory loading, eligible-choice loading and explicit handle refresh
admit an account owner. Read and write settlement retains the existing captured
leases, generation and token checks. A physical old request may settle later;
it cannot remove a successor read, release its write lane or publish its result.
Retirement detaches its account observation and drops old tracker attachments.
Settings listeners remain site-scoped until controller disposal.

Explicit forget and setting changes retain their existing reset/refresh policy.
Same-account current-user refresh still advances permission revision, preserving
an admitted write lane and applicable composer receipts. Same-account directory
caching, shared reads and the eight released-board snapshots retain their prior
behavior. Reacquiring a released handle under a new account reloads its snapshot.
Closing the controller stops account admission and detaches observations before retiring
its document handles.

Controller regressions reproduce old snapshot, directory and eligible-permission
retention on bare request-session retirement. Gated tests cover late reads and
writes, successor coalescing, batched listener readmission and an earlier
retirement observer. Existing tests cover public access, permission refresh,
settings, tracker attachment, composition and released-handle retention.
