# Voice call lifetime

`VoiceController` keeps the public call API, account identities, video-view
watches, and device preferences. Each account's private
`_VoiceRoomDirectory` owns room snapshots, linked rooms, request identity,
HTTP/live precedence, capability state, cursors, and directory/room subscriptions.
`_VoiceRoomEvents` reduces the sealed room events and coordinates directory and
active-call updates, notices, and incoming signal envelopes. It borrows the
existing directory and call manager without retaining another room or call copy.
The directory keeps subscription, cursor, and account delivery guards. The
session keeps roster removal, stage publication, and media reconciliation policy.
The facade coordinates retained calls with embedded Chat.

Open-room offers can introduce an attested sender before the roster arrives.
That provisional update reaches the listed room and active call. Stage rooms
wait for the roster. Signal delivery rechecks active media after provisional
roster synchronization and before its ordered batch. An admitted batch finishes
on its captured media even if a call is replaced while a signal is awaited.
`roomListenable` publishes listed-room and join-loading changes independently of
call controls, incoming rings, embedded Chat, and device preferences.
`_VoiceCallManager` serializes room transitions and coalesces matching pending
joins under the captured account identity. Its admission identity also fences
incoming-answer continuations.

`VoiceIncomingCalls` owns incoming admission, ring subscriptions, bounded replay
history, expiry, system presentation, and answer continuations. Its room access,
join access, and navigation collaborators expose the existing authorities
without importing the controller or shell. Private adapters in the controller
library compose these capabilities. The owner borrows the system-call bridge;
the controller disposes that bridge after owner and call-manager shutdown.

A ringing state owns its expiry timer and pending, local, or system presentation.
Taking a ring replaces it with an answer capability and cancels expiry before
room resolution. That capability retains the original account and request lease,
plus the join admission identity, through navigation and privacy confirmation.
The taken answer remains an admission tombstone so duplicate system answers
cannot repeat resolution or failure handling. A fresh join, replacement ring,
account retirement, or close invalidates the continuation. The bounded replay
history survives ring and answer retirement.

Call owners report answer retirement or a joined room through transition methods
rather than mutating admission. Late presentation checks the original ring
identity and ends an obsolete presentation after expiry or replacement. Close
cancels ringing and subscriptions synchronously. Its asynchronous drain is
idempotent and does not wait for a presentation response. A presentation that
finishes after close is ignored, so it cannot touch the retired bridge.

System-answer navigation preserves the original continuation across privacy
reads and navigation callbacks. It performs no asynchronous privacy read when
the warning does not apply. Local answering still returns the accepted room for
the existing app flow to navigate and confirm privacy.

A system answer never joins a peer-to-peer room before the warning is
accepted. When the warning applies, the answer parks: the room opens, the
answered system call stays up with nothing joined, and the incoming-call banner
asks the user to confirm in the app. The confirmed join reuses the answered
system call. Declining the warning ends that call, and an answer left
unconfirmed for `voiceAnswerConfirmationWindow` fails it. A join that has
started since then owns the system call, so a late deadline leaves it alone.

The system call UI names a caller by username and site host, never by the
caller's chosen display name. A ring rings for at most `voiceRingDuration`
from receipt, whatever its `ring_seconds` or `sent_at` claim.

Each `_VoiceCallSession` exists before preference or credential acquisition.
It owns its call snapshot, server participant identity, media, signal batcher,
heartbeat and state requests, idle tracker, camera queue and revisions, and
participant-volume claims. These private owners share the controller library
through Dart parts. They introduce no new exported transport or UI API.

Closing a session installs one completion before retiring work. Retirement
invalidates asynchronous continuations and cancels timers and queued signals.
Media disposal starts before credentials or the server leave request are
awaited. Membership cleanup is memoized across explicit leave, supersession,
and failed acquisition. The first close preserves its server-notification
decision, including local-only retirement. A renewed LiveKit participant ID
stays on its original session through cleanup.

A close before snapshot publication also seals the attempt and disposes any
media already created. It drains actual acquisition so late resources cannot
escape. A pre-acquisition wait for device preferences can finish on retirement;
it cannot create media afterward. Push-to-talk restoration still precedes any
microphone opening.

Ordinary leave waits for server settlement, media disposal, and CallKit end.
It does not wait for an in-flight heartbeat that may itself have requested
leave. Full manager close also drains admitted joins and outstanding session
requests before the controller disposes its borrowed system-call bridge.
Terminal owners are released by identity so old cleanup cannot clear a newer
call. The controller still retires UI listeners synchronously.

Camera device preferences outlive calls. Capture queues, cancellation revisions,
automatic restoration, and participant-volume claims belong to one session.
A late read or capture continuation checks its original owner before applying
anything. Room directory retirement and displayed-site changes do not end a
retained call. Explicit account removal does.

The owning controller, media, mesh teardown, signaling, app lifecycle and
CallKit tests pin the protocol. The controller tests also gate prepublication
media, preference restoration, repeated leave and late failed connection work.

Video presentation borrows `VoiceVideoHandle` values from media. A handle exposes
only a Flutter binding and the current native track descriptor. Each media
session caches handles by provider object identity, so unchanged video keeps its
notification and renderer identity. LiveKit descriptors read the current native
track after provider restarts. `voice_video_adapter.dart` owns provider rendering
and the private WebRTC native-owner lookup. Views and PiP never receive capture
controls. Renderer disposal releases only its attachment and empty native bridge
stream. Capture stop and disposal remain with the call's media owner.
