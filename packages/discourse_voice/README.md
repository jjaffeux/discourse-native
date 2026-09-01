# discourse_voice

This package is the native ownership boundary for the always-bundled Voice
room integration. It contains the iOS CallKit adapter and the reviewed
`flutter_webrtc` fork used by the application's media transports.

The Dart module, UI, controllers, diagnostics, and media integrations live in
`../../lib/src/plugins/voice` and are part of every application manifest.
The main package depends on this bridge, so every iOS app graph registers
`DiscourseVoicePlugin`; this package deliberately has no dependency back on
the main package.

The source and provenance record for the WebRTC fork remain owned here under
`third_party/`. Each application pubspec activates that reviewed path because
Dart Pub does not honor dependency overrides from transitive packages.
