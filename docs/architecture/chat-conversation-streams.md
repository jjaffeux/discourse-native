# Chat conversation stream lifetimes

`ChatController` remains the application and plugin facade for channel and thread readers. Each retained target has one private `_ChatConversationStream` owner in the controller library. The owner keeps its window, notifier, request tickets, pending live IDs, Store pins, notice timer, and receipt owner lifetime together. A snapshot lookup does not retain a target. A draft or view can retain a target before it has a window, and the notifier is created only when observed.

Canonical messages remain in Store. The stream holds ordered server IDs and a separate optimistic local overlay. The existing `ChatMessageTimeline` reductions preserve contiguous bounded history, anchor placement, hidden-deletion slots, and live-edge seam admission. The owner synchronizes Store pins and removes retired local rows before publishing a new window. Canonical rows are pinned while a view is active. Optimistic rows stay pinned until their overlay retires.

A replacement fetch cancels both directional page tickets and the old notice. It preserves the target's notifier, pending live IDs, and read drain. An old response or cleanup must still own its original owner and request identity before it changes Store or window state. Live arrivals park behind an anchored window until forward paging reaches the present.

Window abandonment and target retirement have different scopes. Channel revocation abandons page work, attempt time, parked arrivals, and notices, then publishes the unavailable state through the existing notifier. Eviction, account forget, and controller disposal retire the whole target, including read work and Store pins. Forget detaches all old site owners before publishing empty values, so a listener that looks up the same target receives a new owner. Old notifiers remain available for widgets to detach. Eviction and disposal can dispose their notifiers.

Each stream attaches a standalone `ChatReadReceiptOwner` for read admission, optimistic projection, serialized delivery, receipt eviction holds and retirement. The facade captures a `ChatReadReceiptSnapshot` with the original account lease, canonical membership and root-window facts. Rejected ticks do not retain a conversation. Sealed channel and thread admissions carry projection policy. The facade applies those projections through existing channel and thread update authorities, notification deltas and publication. Store remains canonical.

Projection precedes queueing and credential lookup, preserving reentrant publication ordering. The receipt owner retains the newest queued cursor and each admitted caller joins the active drain. Duplicate or older cursors during delivery and stale-count cleanup complete immediately without another delivery. Every queued admission retains its original lease. Replacing a page leaves reads alive. Retiring the stream disowns its receipt owner, so an old account cannot consume a successor account's receipt. Failed receipts keep the existing optimistic cursor. A controller-owned `ChatReadReceiptRetries` map retains only the newest undelivered cursor and its account lease per site and target. A later visible observation retries that cursor or a newer one. Successful delivery clears older owed cursors. The map survives window eviction without preventing it, discards stale leases on access, and clears on account forget or disposal. No failure starts an automatic retry. Channel directory and settings writes remain in the account-bound `_ChatChannelDirectory`.

The controller arbitrates conversation retention across the ordered stream registry. Directory retirement disowns channel work independently of retained conversations. Drafts, pin-list snapshots, thread detail, membership writes, and directory revocation retain their existing policies. Site-wide hidden-deletion knowledge remains shared because a canonical message can occupy both root and thread projections. `ChatSendCoordinator` still owns send ordering and reconciliation, and `ChatLiveSyncCoordinator` still owns subscriptions and view claims.

Focused controller, thread, conversation, timeline, stream, and viewport lifecycle tests pin these contracts. The controller suite includes seeded event corpora and controlled request races. These tests verify behavior through the public facade without inspecting owner fields.

`ChatViewLifetime` owns the mounted channel, thread, and channel-thread-list panes' shell subscription and viewing claim. Each pane keeps its own target and token. Channels acquire after the frame because acquisition can update a sibling header; threads keep their immediate initial acquisition. Reactivation calls the pane's existing refresh action. Navigation requests, timezone listeners, and read dwell remain with their existing feature owners.

## Deletion event boundary

`ChatDeletionEvent` decodes single and bulk MessageBus deletion deliveries inside
the Chat module. The live coordinator passes immutable typed IDs, deletion time,
actor and single-delete successor cursor to the existing canonical reducers.
Raw deletion JSON stops at that decoder. Missing or malformed deletion times use
one clock sample per delivery, shared by canonical message tombstones and retained
thread-original projections. Bulk IDs retain their delivery order and duplicates;
invalid entries are ignored as before.

The root/thread delivery rules are unchanged. Thread deliveries skip the original
message because the root owns its non-idempotent mutations. Bulk thread delivery
retains the explicit original-message skip. Canonical reducers still decide
whether deleted records remain inspectable, preserve hidden paging slots, update
read/last-message cursors and record write/read authority. A typed single/bulk
boundary removes duplicated wire parsing without introducing a general event
framework or changing subscriptions, account admission or durable call work.

Live-sync, Chat controller and thread-controller tests exercise these reducers.
An advancing-clock regression pins the shared fallback timestamp for single and
bulk deletions; boundary tests pin invalid IDs, server timestamps and snapshots.
