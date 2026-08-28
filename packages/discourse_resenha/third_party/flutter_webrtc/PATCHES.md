# Local patches

This directory vendors the published `flutter_webrtc` 1.6.0 package from
<https://pub.dev/packages/flutter_webrtc/versions/1.6.0>.

- Archive SHA-256: `e997161d7da3adedd3d430691b20931b0b4d96fa48bb60938d9ba0bf6fca98be`
- Upstream source: <https://github.com/flutter-webrtc/flutter-webrtc/tree/v1.6.0>

The archive is the review baseline. The sections below enumerate every known
local delta; this file is not a claim that the directory is otherwise
byte-for-byte identical to a Git checkout, because package-manager metadata is
not part of the published archive.

## iOS privacy manifest

The upstream iOS screen-broadcast reader calls `mach_absolute_time()` to create
elapsed video-frame timestamps, but version 1.6.0 does not provide a privacy
manifest for that required-reason API.

This copy adds `PrivacyInfo.xcprivacy` to the `flutter_webrtc` Swift package and
CocoaPods resource bundle. It declares the System Boot Time category with
approved reason `35F9.1`, for measuring elapsed time between events inside the
app.

Files:

- `ios/flutter_webrtc/Sources/flutter_webrtc/PrivacyInfo.xcprivacy`
- `ios/flutter_webrtc/Package.swift`
- `ios/flutter_webrtc.podspec`

Introduced with the vendored package in commit `b4d47550958766790d2c1ea2fa1ef29328dc9fcc`.

## Darwin remote-track identity

The upstream `FlutterRTCMediaStream` implementation constructs a new Dart-side
track identifier while reading remote stream tracks. Resenha needs the native
WebRTC track identifier to stay stable across the stream and renderer APIs, so
the iOS/macOS/common Darwin copies now preserve `trackId`.

Files:

- `common/darwin/Classes/FlutterRTCMediaStream.m`
- `ios/flutter_webrtc/Sources/flutter_webrtc/FlutterRTCMediaStream.m`
- `macos/flutter_webrtc/Sources/flutter_webrtc/FlutterRTCMediaStream.m`

Commit: `46169d8a2a22c5667a62791ccb17974404316bd0`.

## Awaited native log severity

The published logger setter returns before its native `setLogSeverity` method
finishes. Resenha diagnostics must know whether native logging was installed
before reporting capture as active, so the local API returns and awaits that
operation.

Files:

- `lib/src/helper.dart`
- `lib/src/native_logs_listener.dart`

Commit: `7400253b0de111c79957416ebf6b1df8c5da2831`.

## Renderer track lifecycle

The published renderer binds videos by stream and can keep stale native track
state after a track is replaced or detached. Resenha switches camera, screen,
and remote participant tracks on a long-lived renderer. The local patch adds a
track-aware renderer binding, clears bindings deterministically, and mirrors
that behavior across Android, Darwin, C++, and Dart implementations.

Files:

- `android/src/main/java/com/cloudwebrtc/webrtc/MethodCallHandlerImpl.java`
- `common/cpp/include/flutter_video_renderer.h`
- `common/cpp/include/flutter_webrtc_base.h`
- `common/cpp/src/flutter_peerconnection.cc`
- `common/cpp/src/flutter_video_renderer.cc`
- `common/cpp/src/flutter_webrtc.cc`
- `common/cpp/src/flutter_webrtc_base.cc`
- `common/darwin/Classes/FlutterWebRTCPlugin.m`
- `ios/flutter_webrtc/Sources/flutter_webrtc/FlutterWebRTCPlugin.m`
- `lib/src/native/rtc_video_platform_view_controller.dart`
- `lib/src/native/rtc_video_renderer_impl.dart`
- `macos/flutter_webrtc/Sources/flutter_webrtc/FlutterWebRTCPlugin.m`

Commit: `b401810ff43d3e20fe4bc41ece6fee33722dd60f`.

## Verifying the review diff

From the Resenha package root, run:

```sh
dart run tool/flutter_webrtc_contract.dart
```

The check downloads only the official pub.dev metadata and archive, verifies
the archive SHA-256 above, and compares every regular file except this manifest.
It passes only when the differing files are exactly the inventory above; empty
package-manager metadata directories are deliberately outside the file contract.
Any additional vendored source difference must be documented here before
release.

Remove this vendored copy and restore the hosted dependency only after an
upstream release provides equivalents for every patch above. Then run
`flutter pub get`, repeat the iOS archive privacy inspection, and exercise
Resenha track replacement on each supported native platform.
