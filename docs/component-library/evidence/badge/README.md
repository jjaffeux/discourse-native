# Badge browser evidence

Implementation source: `08e7042a27dc34f6db11399e26709d622fe14a7a`.

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

Exterior-ring followup: `ring-before/` was rendered from the previous source
`45d85a99e12e9907a8c8d3ed882c8920b52d0f18`; current top-level Flutter exports
include the correction. `reference-ring-css.json` preserves exact compiled CSS
rules; `ring-pixel-regression.json` records the reproduced tint and pixel checks.
Use `--dart-define=BADGE_RING_ONLY=true` with the harness for only ring states;
`--dart-define=BADGE_EXPORT_DIR=/absolute/output/path` selects an existing output
directory. This followup involved no UI access. Live focused/invalid comparison
and native review remain pending.
