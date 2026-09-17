# Local patches

Discourse Native vendors the published `flutter_widget_from_html_core` 0.17.4
archive from <https://pub.dev/packages/flutter_widget_from_html_core/versions/0.17.4>.

- Archive SHA-256: `530f2e3cc57be1a00f8bfae1b0000064e8a6df0cf1fb4d48a80f85afde9b39b7`
- Upstream source: <https://github.com/daohoangson/flutter_widget_from_html/tree/master/packages/core>

The published archive is the baseline. Every local difference is listed below.

## Repeated default styles

HTML build trees share a bounded, isolate-local cache of parsed default CSS,
keyed by the complete ordered output of each default-style callback. Callbacks
still run for every element, preserving attribute-dependent defaults and plugin
behavior. Sharing the parser templates across bodies avoids reparsing the same
defaults as chat rows enter the viewport. The cache stores CSS syntax only, not
widgets, contexts, build trees, or resolved theme state.

Each lookup returns independent declarations, expressions, identifiers and
Dart-style metadata. Only simple literals with faithfully cloneable metadata
are cached. Complex functions, legacy declarations and other expression forms
retain the upstream parser path. The cache admits at most 64 style strings of
at most 4,096 characters each. Existing entries are not evicted while a body is
being built. When the shared pool fills, each body retains its original bounded
local cache for additional styles; earlier bodies cannot crowd out local reuse.
Inline CSS parsing, conversion order and mounting are unchanged.

Custom-style callback output uses the same bounded syntax cache as defaults.
The complete ordered map remains the key and callbacks still run for every
element, so changes in attributes, theme or plugin state are respected. Empty
default/custom maps bypass parsing. Custom declarations use the same literal
eligibility, deep-copy guarantees, 64-entry shared/body-local limits and
4,096-character cutoff. This avoids reparsing identical link and paragraph
overrides as rich chat rows enter the viewport. It retains no HTML or message
content. Inline CSS still applies after custom styles.

Files:

- `lib/src/internal/core_build_tree.dart`
- `lib/src/internal/default_styles_cache.dart`
- `test/default_styles_cache_test.dart`
- `test/default_styles_rendering_test.dart`

## Provenance metadata

Files:

- `PATCHES.md`
- `tool/vendor_contract.json`

From the application repository root:

```sh
flutter test --no-pub packages/flutter_widget_from_html_core/test
dart run tool/vendor_provenance_contract.dart
```

Remove the fork and both application overrides after an upstream release
provides equivalent reuse and mutation isolation. Regenerate both lockfiles,
run cooked rendering and selection tests, and repeat the native conversion
profile before upgrading.
