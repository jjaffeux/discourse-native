# Badge browser evidence

Implementation source: `302f4c3b3082d87a0e2fd1a1b46be873e7d14c27`.

`reference-*` PNGs and computed-style JSON are live Chrome captures from
https://ui.shadcn.com/docs/components/base/badge on 2026-09-09.
`flutter-*` PNGs and measurements are actual widget-test renderer output,
not screenshots of a running native app. The source harness is saved as
`export-harness.dart.txt`; copy to `test/badge_export_test.dart` to reproduce
on this macOS host, then run `flutter test --no-pub test/badge_export_test.dart`.
It uses system font files and is intentionally not a portable CI test.

Neutral images use a reference-color/radius adapter for comparison. Host-palette
images use real Light/Dark/Forest/Plum themes. Each matched neutral image is
638×288 pixels at device pixel ratio 1. The reference has Geist; Flutter uses
macOS SF. This is a geometry/state comparison, not pixel equality. Large RTL
examples use 360px and 200% text. The profile overlay retains default route
scaling; its filename describes the underlying fixture, not overlay scaling.

Native application review and VoiceOver remain pending. See `../../badge.md`
and `../../badge-native.md` for observations, limitations, source mappings and
signed build identity. No native app was launched during the browser-only slot.
