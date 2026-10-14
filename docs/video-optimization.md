# Video upload optimization

Post, private-message, chat, and nested-editor uploads use
`ComposerMediaOptimizer` before upload size validation. Video inputs are staged
in temporary storage and encoded through the app-owned
`packages/discourse_video_optimizer` Flutter plugin. Picked and dropped files use
the same path. Linux and other unsupported platforms upload the original.

The existing Native `DAttachment` processing state displays **Optimizing video…**
and a **Cancel video upload** action. Cancellation removes the upload, stops
preparation/native encoding, and releases temporary files. When preparation ends,
the status changes to the existing network upload percentage and cancel action.
Post placeholders and chat attachments use this same component.

## Policy

- Consider MP4, MOV, M4V, WebM, MKV, AVI, and 3GP files between 1 MiB and 2 GiB.
  Native codecs decide which of these containers they can actually decode.
- The original extension must pass the normal composer allowlist. Only attempt
  optimization when the forum also allows the resulting `.mp4` filename.
- Export H.264 video and AAC audio to MP4, limiting the long edge to 1920 and
  the short edge to 1080. Never upscale. Keep rotation, aspect ratio, and timing.
- Apple uses AVFoundation's 1080p H.264/AAC export preset, including its native
  HDR-to-SDR handling and network-optimized MP4 layout. Android uses Media3
  Transformer with explicit HDR-to-SDR OpenGL tone mapping and an approximately
  5 Mbps target at 1080p, reduced for smaller frames.
- Validate output dimensions, aspect ratio, duration, and audio-track presence.
  Keep the original for multiple video/audio tracks, unsupported codecs or
  dimensions above 8K, invalid output, or an output that is not smaller.
- A missing plugin, unavailable encoder, storage error, timeout, or other
  preparation failure falls back to the original upload. It does not bypass the
  forum's existing file-size or format rules. Compression is not guaranteed to
  bring an attachment under the forum's limit.
- Serialize encoding across composers. Copy input streams with awaited disk
  writes to bound memory. Native exports have a ten-minute timeout; Dart also
  guards unresponsive platform calls. Retries reuse successful prepared output.
- The source is never modified. Temporary output belongs to the upload until
  success, removal, cancellation, or composer disposal.

This is foreground preparation, not a persistent background job. An OS codec
failure after backgrounding follows the original-file fallback path. Image
optimization retains its existing site-controlled policy.

## Native integration and checks

The plugin registers on iOS 15+, macOS 12+, and Android API 23+. It includes both
Swift Package Manager and CocoaPods support. Android Media3 is pinned to 1.9.2
to match the existing `video_player_android` backend; upgrade these together.
The Android application runner registers the plugin. CI builds the Android app
and runs the plugin's native policy tests.

Focused checks:

```sh
flutter test test/composer_video_optimizer_test.dart \
  test/composer_upload_attachment_test.dart test/composer_upload_preparation_test.dart
swift test --package-path packages/discourse_video_optimizer
```

The Swift tests generate real video/audio fixtures and exercise export, rotation,
downscaling, and cancellation. Android's `VideoPolicyTest` checks sizing and
output validation. Device codec/HDR behavior still requires real-device testing;
JVM tests and compilation do not exercise MediaCodec hardware.
