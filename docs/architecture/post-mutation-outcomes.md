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
reads and retain their existing read contracts. Notice, flag, like, checklist,
bookmark and composer protocols keep their existing owners.

## Projection ownership

`TopicDataSession` repairs canonical records through `Store`. Repair returns
freshness after all selected-post batches complete. A failed later batch
publishes no partial repair. Original credentials, account leases and removal
revisions still govern publication. A failed repair marks the topic for a fresh
read on its next opening.

Accepted deletion closes only the captured composer while its opening account
remains current. Accepted selected-post writes clear the captured selection even
when repair fails. Refused and not-sent writes retain selection.

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
