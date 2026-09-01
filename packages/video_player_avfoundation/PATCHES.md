# Local patches

Discourse Native vendors the published `video_player_avfoundation` 2.11.1
package under `packages/video_player_avfoundation`, from
<https://pub.dev/packages/video_player_avfoundation/versions/2.11.1>.

- Archive SHA-256: `436fd029bd1c1e303b2d95ebd76948893f3c28dab286e7235ba9dd7b22533bf0`
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

Remove this fork and both `dependency_overrides` after an upstream release no
longer emits the Swift-import warning. Then regenerate both lockfiles and run a
clean macOS build.
