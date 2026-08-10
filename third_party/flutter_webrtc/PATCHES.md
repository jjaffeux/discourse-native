# Local patches

This directory vendors the published `flutter_webrtc` 1.6.0 package from
<https://pub.dev/packages/flutter_webrtc/versions/1.6.0>.

- Archive SHA-256: `e997161d7da3adedd3d430691b20931b0b4d96fa48bb60938d9ba0bf6fca98be`
- Upstream source: <https://github.com/flutter-webrtc/flutter-webrtc/tree/v1.6.0>

## iOS privacy manifest

The upstream iOS screen-broadcast reader calls `mach_absolute_time()` to create
elapsed video-frame timestamps, but version 1.6.0 does not provide a privacy
manifest for that required-reason API.

This copy adds `PrivacyInfo.xcprivacy` to the `flutter_webrtc` Swift package and
CocoaPods resource bundle. It declares the System Boot Time category with
approved reason `35F9.1`, for measuring elapsed time between events inside the
app. No plugin source code is changed.

Remove this vendored copy and restore the hosted dependency after an upstream
release provides an equivalent plugin-owned manifest. Then run
`flutter pub get` and repeat the iOS archive privacy inspection.
