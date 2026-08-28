# discourse_resenha

This package is the ownership boundary for the optional Resenha voice-room
integration. It contains the Dart module, native adapters, LiveKit and WebRTC
dependencies, and the reviewed `flutter_webrtc` fork used by those transports.

Applications opt into Resenha by depending on this package and adding
`resenhaModule` to their `PluginManifest`. Merely importing or running
`discourse_native` does not add Resenha's SDKs or native registrations.

The full application composition lives at `../../profiles/full`. Dart Pub does
not honor a dependency override from a transitive package, so that application
mirrors this package's `flutter_webrtc` path override. The source and
provenance record for the fork remain owned here under `third_party/`.
