# Android development

Use the Flutter version pinned in `.fvmrc`, Java 17, and an Android SDK with
platform 36, build tools 36.0.0, and NDK 28.2.13676358. Set `ANDROID_HOME` to your
SDK directory and put Flutter and Java on `PATH`.

Run these commands from the repository root:

```sh
flutter pub get
flutter build apk --release
```

The APK is written to `build/app/outputs/flutter-apk/app-release.apk`. It supports
Android 7.0 (API 24) and newer, with ARM, ARM64, and x86-64 libraries. Local release
builds use the development signing key for sideloading; store publication needs
a distribution signing configuration.

```sh
adb install -r build/app/outputs/flutter-apk/app-release.apk
flutter test integration_test/android_smoke_test.dart -d <android-device>
cd android
./gradlew :app:connectedDebugAndroidTest :discourse_video_optimizer:testDebugUnitTest
```

Credentials are encrypted with a device-bound Android Keystore key and stored
outside backups. Drafts use private application storage. Browser sign-in returns
through `discourse://auth_redirect`. The app declares microphone and camera
permissions for Voice and attachments; access is requested by the media plugins
when used. Android remote push registration and the iOS-specific system call UI
and picture-in-picture bridge are not implemented.
