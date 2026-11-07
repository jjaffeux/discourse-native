# Notification ingress destination lifetime

`AppRuntime` owns one notification URL queue across controller replacement.
Each ready controller supplies a private destination identity and a retirement
signal. Making navigation unavailable, installing a replacement destination,
or disposing the runtime retires the previous destination after removing its
authority to consume queued URLs.

Delivery remains serial for the current destination. The destination retains
only its active delivery completion, settled by navigation or retirement,
whichever occurs first. Completed taps leave no accumulated retirement listeners. Retirement releases the drain immediately;
it does not wait for an old plugin handler or credential operation to finish.
The pending URL stays in the queue and is replayed through the successor once
that controller is ready. The old navigation future remains observed, including
late failures. Its late result cannot consume a URL or affect the successor's
drain. Shell navigation retains its own disposed/account checks after awaits.

This deliberately improves the former timing contract: a successor previously
waited for a retired destination's pending navigation before receiving any
notifications. Existing replacement coverage now requires replay before that
old future settles. There is no timeout or cancellation promise for arbitrary
plugin code; the destination owns only its delivery authority.

Queue entries retain identity separate from URL spelling. Equal strings are
separate notification taps. The existing sixteen-entry bound can evict an
in-flight entry; its completion removes only that exact entry, preserving a
later equal URL. Stream replacement retains queued taps and rejects callbacks
from the retired source, independently from destination replacement.

Independent concurrent drains per destination would require extra ownership
checks around queue consumption. A destination retirement signal instead
retains the existing single drain, bounded queue, and ordering policy.

`app_runtime_test.dart` holds an old handler across controller replacement and
verifies pending and new URLs reach the successor before the old handler
succeeds or fails. `push_notification_navigation_test.dart` covers equal taps,
queue eviction, source replacement, errors, and the updated prompt-replay
contract. All three changed/new retirement cases failed before this change.
