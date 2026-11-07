# Post mutation outcomes

Post moderation reports server write truth independently from local projection
freshness. `PostMutationOutcome` replaces nullable localized errors for the
single-post and selected-post mutation helpers, owner changes, moves and
permanent deletion.

An accepted result stays accepted when repair fails or its opening account
retires. Its projection is fresh, stale or retired. A refused result carries the
site's refusal category and server messages. A not-sent result describes a
request that did not run, including admission, credential and proven transport
failures. An uncertain result means the write may have reached the site. A
no-change result means the requested state already matches. Retirement before
dispatch has its own result.

The shell copies transport failure details into domain problems. Application
localization belongs to `post_mutation_feedback.dart`. Server-localized messages
remain verbatim. Permanent-delete eligibility and move destination search are
reads and retain their existing read contracts. Flag, like, checklist, bookmark
and composer protocols keep their existing owners.

Single-post moderation commands, including staff notices, share
`_PostCommandOwner` for account admission, per-post locking, credential lookup,
dispatch, uncertain-write recovery and projection repair. Notice commands retain
their captured site, topic, post and lease across navigation. `_PostMutationPolicy`
owns both the notice permission selector used by presentation and its repeated
write admission checks. Shell captures targets and forwards commands.

Notice normalization turns absent or all-whitespace input into removal while
preserving nonempty raw Markdown exactly. An unresolved recovery barrier wins
over an otherwise matching notice. With no unresolved operation, a matching raw
value answers no-change before acquiring a post lock and is checked again after
credential lookup. This preserves idempotent no-op behavior when another write
holds the post or a concurrent read supplies the desired value. Accepted writes
use the same canonical repair and typed freshness outcomes as other post commands.

A separate notice transaction would duplicate the shared dispatch/recovery
protocol. The typed command case keeps notice-specific admission and HTTP inputs
explicit without adding a callback-based mutation framework.

## Projection ownership

`TopicDataSession` repairs canonical records through `Store`. Repair returns
freshness after all selected-post batches complete. A failed later batch
publishes no partial repair. Original credentials, account leases and removal
revisions still govern publication. A failed repair marks the topic for a fresh
read on its next opening.

Accepted deletion closes only the captured composer while its opening account
remains current. Accepted selected-post writes clear the captured selection even
when repair fails. Refused and not-sent writes retain selection.

Selected-post selection and admission share one typed entry in `ShellController`.
Its active attempt retains the original lease, ordered post IDs, immutable command
inputs and `TopicDataSession` holders through dispatch and repair. A closed command
switch sends delete, merge, move and owner changes. Settlement derives selection
removal from the outcome and checks the captured entry and attempt identities.
Account retirement cannot clear or unlock a replacement account's selection.

`PostMoveOutcome` exposes a destination only for accepted completion with a
current opening target. A retired accepted move keeps its acceptance and has no
navigable destination. Known destinations are invalidated when the write settles.
A lost new-topic move response never causes a title-based destination guess.

## Unknown writes and recovery

Uncertainty lives in the original account's topic data session, separately from
transient write holders. Each unresolved operation records its identity and
captured post scope. Permanent topic deletion records a whole-topic scope.
Conflicting admission returns not-sent with a read-only recovery capability.
The topic deletion and recovery header also respects unresolved admission.

An uncertain write attempts a complete reread before releasing its ordinary
write holders. A failed reread retains unresolved admission. Closing a dialog,
changing tabs and older incidental reads do not clear it. Explicit recovery and
explicit topic refresh can reread that captured scope without repeating a write.
Only complete publication for the same current recovery identity clears it.
Account retirement discards that account's state.

Whole-topic recovery reads current availability and repairs the union of
captured, currently held and newly discovered stream IDs. Topic metadata cannot
replace the newly repaired post bodies. Connectivity failures, forbidden reads
and unexplained 404 responses never prove permanent destruction.

A fresh recovery permits a newly captured user decision. It does not prove that
the earlier request caused the observed state. The original uncertain dialog
keeps its submit action disabled after refresh and offers only refresh or close.

## Presentation lifetime

Post actions retain their rendered account, tab and destination owner. Dialogs
return typed outcomes to their opener so an accepted-but-stale refresh action
survives dialog disposal. Toast actions use the same captured reader guard and
cannot publish feedback into a successor reader.

A successful move navigates to its destination without a source-reader refresh
toast. If source repair failed, its next opening requests fresh data. All controls
use existing Native components.

## Optimistic likes

The shell retains gesture admission, credentials and the per-post write holder.
After credentials resolve, `TopicDataSession.beginLike` compares the rendered
liked state with the current canonical post before admitting a `PostLikeWrite`.
A gesture whose state already changed sends no duplicate request. An admitted
gesture still uses updated counts and permissions from the current post; changed
permissions alone do not revoke an already accepted gesture.

The account session owns each like ticket and its optimistic projection. Failure
restores the captured current liked state, count and like/unlike permissions only
while those four fields still equal the ticket's guess. A newer differing like
projection keeps authority; unrelated body edits survive rollback. This is exact
optimistic-field ownership, not an additional read freshness epoch. Retirement
and a successor ticket cannot inherit an earlier ticket's settlement authority.
An empty successful response retains the guess until the next canonical read.

A shell-only guard would close duplicate dispatch but leave rollback decisions
split between the shell and canonical post owner. The bounded ticket keeps these
decisions together without adding a general mutation transaction framework.
`post_like_write_ownership_test.dart`, stale-activation and post write-lock tests
cover credential races, rollback, account retirement and gesture compatibility.

## Feedback belongs to the rendered action owner

Likes and quick reactions use `PostActionOwner` for both admission and feedback,
matching the owner check used for typed moderation feedback. Their asynchronous
work is invoked only after capturing its owner. A completion may still update
its account's data, but a toast or liker-panel refresh requires the originating
account lease, tab, destination identity, and post to remain current.

A mounted widget and unchanged shell alone do not establish that authority:
account retirement or navigation can occur before the next Flutter frame.
`post_rendered_action_ownership_test.dart` holds the HTTP response through those
transitions and verifies that current actions still report errors while retired
ones remain silent.
