#!/usr/bin/env bash
# Run the offline native metadata regressions without launching a Flutter app.
set -euo pipefail

plugin_dir="$(cd "$(dirname "$0")/.." && pwd)"
flutter_sdk="${1:?Usage: test_metadata_lifecycle.sh /path/to/flutter-sdk}"
framework="$flutter_sdk/bin/cache/artifacts/engine/darwin-x64/FlutterMacOS.xcframework"
if [[ ! -d "$framework" ]]; then
  echo "Missing cached macOS Flutter framework: $framework" >&2
  exit 1
fi

native_dir="$(mktemp -d "${TMPDIR:-/tmp}/video-metadata-tests.XXXXXX")"
trap 'rm -rf "$native_dir"' EXIT
cp -R "$plugin_dir/darwin/video_player_avfoundation/Sources" "$native_dir/Sources"
cp -R "$plugin_dir/darwin/RunnerTests" "$native_dir/Tests"
ln -s "$framework" "$native_dir/FlutterMacOS.xcframework"
cat > "$native_dir/Package.swift" <<'SWIFT'
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "VideoMetadataTests",
  platforms: [.macOS(.v13)],
  targets: [
    .binaryTarget(name: "FlutterMacOS", path: "FlutterMacOS.xcframework"),
    .target(
      name: "video_player_avfoundation_macos", dependencies: ["FlutterMacOS"],
      cSettings: [
        .headerSearchPath("../video_player_avfoundation_objc/include/video_player_avfoundation_objc")
      ]),
    .target(
      name: "video_player_avfoundation_objc",
      dependencies: ["video_player_avfoundation_macos", "FlutterMacOS"]),
    .target(
      name: "video_player_avfoundation",
      dependencies: ["video_player_avfoundation_objc", "FlutterMacOS"],
      resources: [.process("Resources")]),
    .testTarget(
      name: "VideoMetadataTests",
      dependencies: ["video_player_avfoundation", "video_player_avfoundation_objc", "FlutterMacOS"],
      path: "Tests"),
  ])
SWIFT

# The explicit allowlist is intentional: the same upstream test file contains live-media tests.
CLANG_MODULE_CACHE_PATH="$native_dir/module-cache" \
SWIFTPM_MODULECACHE_OVERRIDE="$native_dir/module-cache" \
swift test --package-path "$native_dir" --disable-sandbox \
  --cache-path "$native_dir/cache" --config-path "$native_dir/config" \
  --security-path "$native_dir/security" \
  --filter 'VideoPlayerMetadataTests|VideoPlayerTests/(loadTracksWithMediaTypeIsCalledOnNewerOS|videoOutputIsConfiguredWithBT709ColorProperties)'
