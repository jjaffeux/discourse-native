# Compatibility application profile

This wrapper is retained for release tooling and existing launch
configurations. It uses the same complete bundled manifest as the repository
root, including Voice, WebRTC, LiveKit, and CallKit. There is no core-only
application graph.

This compatibility wrapper includes iOS, macOS, Linux, and Android hosts.
Build Android releases from this directory. See
[Google Play internal testing](../../docs/android-testing.md) for signing and upload setup.

Run commands from this directory:

```sh
flutter pub get
flutter run -d macos
flutter build ios --no-codesign
flutter build linux
flutter build appbundle
```

The repository-root app can be run directly with `flutter run`. The legacy
`lib/main_core.dart` target is also an alias of the complete bundled manifest,
so no launch target removes Voice.
