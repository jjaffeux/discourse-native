# Voice call lifetime

`VoiceController` keeps the public call API, account and room directories,
incoming-ring routing, video-view watches, and device preferences.
`_VoiceCallManager` serializes room transitions and coalesces matching pending
joins under the captured account identity. Its admission identity also fences
incoming-answer continuations.

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
