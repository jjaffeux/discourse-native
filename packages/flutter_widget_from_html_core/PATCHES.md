# Local patches

Discourse Native vendors the published `flutter_widget_from_html_core` 0.17.4
archive from <https://pub.dev/packages/flutter_widget_from_html_core/versions/0.17.4>.

- Archive SHA-256: `530f2e3cc57be1a00f8bfae1b0000064e8a6df0cf1fb4d48a80f85afde9b39b7`
- Upstream source: <https://github.com/daohoangson/flutter_widget_from_html/tree/master/packages/core>

The published archive is the baseline. Every local difference is listed below.

## Repeated default styles

An HTML body's build trees share a bounded cache of parsed default CSS, keyed
by the complete ordered output of each default-style callback. Callbacks still
run for every element, preserving attribute-dependent defaults and plugin
behavior. The cache ends with that body's trees; it does not store widgets,
contexts, or cross-body theme state.

Each lookup returns independent declarations, expressions, identifiers and
Dart-style metadata. Only simple literals with faithfully cloneable metadata
are cached. Complex functions, legacy declarations and other expression forms
retain the upstream parser path. The cache admits at most 64 style strings of
at most 4,096 characters each. Existing entries are not evicted while a body is
being built. Inline and custom CSS parsing, conversion order and mounting are
unchanged.

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
