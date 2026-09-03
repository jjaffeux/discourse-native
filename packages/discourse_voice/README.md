# discourse_voice

This package is the native ownership boundary for the always-bundled Voice
room integration. It contains the iOS CallKit adapter and the reviewed
`flutter_webrtc` fork used by the application's media transports.

The CallKit adapter places outgoing calls for room joins and presents
incoming direct calls the Dart side reports from the plugin's ring channel;
answer, decline, mute, and end actions taken in the system UI flow back over
the same method channel. It holds one system call at a time, and a join that
follows a system answer reuses that call instead of placing another.

The Dart module, UI, controllers, diagnostics, and media integrations live in
`../../lib/src/plugins/voice` and are part of every application manifest.
The main package depends on this bridge, so every iOS app graph registers
`DiscourseVoicePlugin`; this package deliberately has no dependency back on
the main package.

Room tiles show the server's active participant roster; the Join room button
reflects this client's call state. An account connected from another client
can therefore appear before joining here. As in core's Voice client, leaving
or failing to connect after a successful server join removes the local
participant from cached rooms immediately, without waiting for a roster
broadcast. Later server updates remain authoritative.

The source and provenance record for the WebRTC fork remain owned here under
`third_party/`. Each application pubspec activates that reviewed path because
Dart Pub does not honor dependency overrides from transitive packages.
