# Dependency audit — 2026-11-24

Updated local main from origin/main (already current), preserving five existing local commits. No push.

## Retained upgrades

Both application lockfiles: cli_util 0.6.0 → 0.6.1; flutter_svg 2.4.0 → 2.5.0; vector_graphics_compiler 1.3.6 → 1.3.7; pasteboard 0.6.1 → 0.6.2; image_picker_ios 0.8.13+15 → 0.8.13+16.

Gemfile.lock: addressable 2.10.0, aws-partitions 1.1311.0, aws-sdk-core 3.272.0, aws-sdk-kms 1.145.0, aws-sdk-s3 1.245.2, domain_name 0.7.20261117, googleauth 1.17.8, httpclient 2.11.0, typhoeus 1.8.0. Fastlane and CocoaPods stay at their declared versions.

## Verification

- 207 tests passed across d_icon_test, d_icon_glyph_test, sidebar_icon_loader_test, composer_upload_picker_test, composer_upload_preparation_test, external_link_test, open_link_test, native_inline_video_playback_test, and inline_video_test (explicit file paths).
- Eight clipboard-specific composer_upload_panel_test tests passed.
- Full composer_upload_panel_test: 51 passed, four failures. All four failures reproduced against the original locked package versions via a separate package configuration: discard-dialog visibility, projected image editing controls, gallery toolbar membership, and gallery Ctrl+Enter. No application edits made for these existing failures.
- macOS debug build passed with the initial candidate graph; retained upgrades were all included. Android-only upgrades were subsequently reverted.
- Both application graphs pass flutter pub get --enforce-lockfile.
- bundle exec fastlane lanes and bundle exec pod --version passed; strict Ruby outdated audit reports no remaining compatible upgrades.
- Cooking and math npm inputs match current registry versions; no npm changes.
- git diff --check passed. No full Flutter suite run.

## Deferred upgrades and limits

Android jni/jni_flutter, url_launcher_android and video_player_android upgrades were reverted: native compilation could not be verified because Rust 1.92.0 lacks armv7-linux-androideabi and aarch64-linux-android standard-library targets. The Android wrapper is profiles/full; building from the package root is unsupported. Kotlin plugin migration warnings remain in existing dependencies.

WebView 1.5.2 requires supported-platform playback/scroll smoke tests; keep the entire family at 1.4.11, including compatibility-wrapper transitives. Voice/LiveKit pins require room smoke tests on supported platforms. Reviewed HTML/WebRTC/AVFoundation forks remain in place. Image 4.13.1 remains excluded after the prior run's ICC regression; this run did not retest it. Major authentication/desktop changes and SDK/upstream-constrained transitives remain deferred. vector_graphics_compiler currently caps xml at 7.0.1. No iOS-device or Linux-runtime smoke test was performed.
