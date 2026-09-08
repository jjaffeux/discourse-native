# Local patches

Discourse Native vendors the published `video_player_avfoundation` 2.12.0
package under `packages/video_player_avfoundation`, from
<https://pub.dev/packages/video_player_avfoundation/versions/2.12.0>.

- Archive SHA-256: `2fc56e537324a19eb649fca991aa308ac961b5406292876fa657b062de461fd8`
- Upstream source: <https://github.com/flutter/packages/tree/main/packages/video_player/video_player_avfoundation>

The published archive is the review baseline. The sections below enumerate
every local difference.

## Swift importer deprecation warning

Apple marks `AVKeyValueStatus` as deprecated for Swift while the upstream
plugin still exposes it through an Objective-C testing protocol. Xcode warns
each time the plugin's Swift target imports that public header, even though the
legacy API is intentionally retained for the plugin's supported OS versions.

The local header wraps only that declaration in Clang's
`-Wdeprecated-declarations` diagnostic scope. Application deprecation warnings
and all other dependency warnings remain enabled.

Files:

- `darwin/video_player_avfoundation/Sources/video_player_avfoundation_objc/include/video_player_avfoundation_objc/FVPAVFactory.h`

## Initialization metadata lifetime

Pending AVAsset callbacks used to retain `FVPVideoPlayer`, and the tracks and
transform requests could start after disposal. The player now owns the temporary
item wrapper and track. Callbacks hold the player weakly, and each stage checks
disposal on the main queue before starting more work or applying a composition.
Completion and disposal release the initialization inputs. Rotation composition
and the existing BT.709 output settings remain covered by native tests.

The pinned factory creates transient wrappers around the actual AVFoundation
item and asset, so weakening those wrappers alone would lose metadata for active
players. No `cancelLoading` call is added: it affects all observers of an asset,
and initialization accepts a caller-provided item. Existing requests may still
finish, but their callbacks cannot keep a retired player alive or advance its
metadata pipeline. This addresses retention until completion, without claiming
an indefinite leak.

Files:

- `darwin/video_player_avfoundation/Sources/video_player_avfoundation_objc/FVPVideoPlayer.m`
- `darwin/RunnerTests/TestClasses.swift`
- `darwin/RunnerTests/VideoPlayerTests.swift`
- `tool/test_metadata_lifecycle.sh`

Run the focused native tests on macOS 13 or later with Xcode and the repository's
pinned Flutter SDK cached locally:

```sh
bash packages/video_player_avfoundation/tool/test_metadata_lifecycle.sh /path/to/flutter-sdk
```

The harness builds the plugin and its existing test sources in a temporary Swift
package, with an explicit allowlist of deferred metadata tests and two offline
configuration checks. It does not launch an app or run the upstream live-media
integration tests. The test harness's macOS minimum does not change the plugin's
iOS 13 / macOS 10.15 deployment targets.

## Provenance metadata

These files record and validate the fork against the official pub.dev archive.

Files:

- `PATCHES.md`
- `tool/vendor_contract.json`

## Verifying the review diff

From the application repository root, run:

```sh
dart run tool/vendor_provenance_contract.dart
```

Remove this fork and both `dependency_overrides` after an upstream release
includes the metadata lifetime fix and no longer emits the Swift-import warning.
Then regenerate both lockfiles and run a clean macOS build.
