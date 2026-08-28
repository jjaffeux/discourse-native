# Full application profile

This is the Flutter application composition which includes
`discourse_resenha`. It has its own dependency lock and generated native
registrants; those artifacts must never be shared with the core application at
the repository root.

The isolated full profile currently supports iOS, macOS, and Linux. Android
remains planned; the root repository's placeholder Android tree is not a full
profile runner and does not establish Android support.

Run commands from this directory:

```sh
flutter pub get
flutter run -d macos
flutter build ios --no-codesign
flutter build linux
```

Run the core profile from the repository root instead. Choosing
`lib/main_core.dart` as a target in this full package changes only Dart
reachability; it does not remove native plugins from the artifact.
