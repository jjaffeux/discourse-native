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

## Launcher icon

The Android icon uses the [Discourse team’s original artwork](https://commons.wikimedia.org/wiki/File:Discourse_icon.svg)
(GPL-2.0; see `artwork/LICENSE`), kept unchanged in `artwork/discourse_icon.svg`.
The source download is
https://upload.wikimedia.org/wikipedia/commons/1/17/Discourse_icon.svg.

Regenerate the Android resources from the repository root with Python 3 and
`rsvg-convert` (librsvg):

```sh
python3 tool/generate_android_icons.py
```

Android 8+ uses a full-bleed black background and the colored speech bubble as
the vector foreground on a 108dp canvas, matching Meta's launcher icon. The dark
outer D is replaced by the background; the bubble is optically centered to
balance its tail and color weight, filling about 72% of the launcher's 72dp
viewport. The launcher supplies the outer shape
and effects. A solid speech-bubble silhouette supports Android 13+ themed icons.
Android 7 uses rounded legacy PNGs at the standard 48/72/96/144/192px density sizes.
