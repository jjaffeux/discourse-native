# Global Chat search account lifetime

`ChatSearchController` retains one account owner per forum. The owner combines
its captured lease, immutable result state, externally observed state ref,
request identity, debounce timer and detachable retirement observation. Existing
query validation, result snapshots, deduplication and server cursor accounting
remain in the controller; search results do not enter canonical message storage.

Retirement removes the exact owner before clearing its timer/request and setting
its old ref to idle. Existing listeners therefore lose private message excerpts
immediately, including first-page hits retained while an append was pending.
This deliberately changes bare invalidation, which previously stopped late
responses but left those hits visible until an explicit forget. Same-account
append loading still retains its existing hits.

An explicit query or ref admission after retirement captures a successor account
and creates a new ref. Old refs remain empty; old retirement callbacks and request
settlement cannot clear or publish into a successor. Ref clearing may reenter the
controller to search, forget or close, so account removal precedes notification.
Retired refs are cleared and dropped rather than disposed while mounted consumers
can still hold them. No timer or lease observation keeps those refs alive.

Confirmed result state includes its query and sort. Retirement clears that
account state rather than replaying a prior account's search. The mounted view
owns its text field, route search words and FocusNode; this unit does not alter
those document inputs or their focus behavior. The unused focus-registration map
and its sole registration were removed: no operation consumed those callbacks.
The mounted view observes ref identity changes when its previous ref withdraws,
then detaches that observation and binds the successor ref. Same-account result
updates still use its existing value-listenable builder. In-channel conversation
search retains its separate existing owner.

Controller tests reproduce retained private excerpts on the old source and cover
old/new refs, late success/failure, earlier retirement observers, ref-listener
successor admission and disposal. A mounted-view regression proves successor results render after withdrawal;
view, entry and loading suites pin the surrounding UI behavior.

## Rendered result activation

A rendered result captures its account ref, search controller, Chat controller,
shell service and forum before its callback can run. Dispatch, navigation after
channel resolution and failure feedback all require that same authority. The
controller's passive `isCurrentGlobalRef` check includes its captured lease; it
does not rely on the view having followed a replacement ref yet. This matters
when retirement notification is deferred until the end of a layout frame.

Same-account query changes do not revoke an already admitted target. Account
retirement or service/site replacement does: an old row waiting for repaint
cannot start a successor-account lookup, and old success/error completions cannot
navigate or display feedback there. No separate navigation dispatcher is added.
Widget regressions cover channel/thread targets, pre-paint callbacks, deferred
layout notification and late resolution/error. Same-owner navigation, query
change and visible-error controls prove the guards still permit active work.
