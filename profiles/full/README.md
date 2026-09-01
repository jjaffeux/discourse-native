# Compatibility application profile

This wrapper is retained for release tooling and existing launch
configurations. It uses the same complete bundled manifest as the repository
root, including Resenha, WebRTC, LiveKit, and CallKit. There is no core-only
application graph.

This compatibility wrapper currently supports iOS, macOS, and Linux. Android
remains planned; the root repository's placeholder Android tree does not
establish Android support.

Run commands from this directory:

```sh
flutter pub get
flutter run -d macos
flutter build ios --no-codesign
flutter build linux
```

The repository-root app can be run directly with `flutter run`. The legacy
`lib/main_core.dart` target is also an alias of the complete bundled manifest,
so no launch target removes Resenha.
