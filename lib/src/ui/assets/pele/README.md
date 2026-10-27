# Bundled Pele runtime

`pele-1.10.0.global.js` is the unmodified `dist/pele.global.js` from the official
[`pele` npm package](https://www.npmjs.com/package/pele/v/1.10.0), matching
[Discourse Pele at 8cd113d](https://github.com/discourse/discourse-pele-theme-component/blob/8cd113d57122f00dfefb145344c02f78d9ba014c/about.json).
Its MIT license is bundled and registered with Flutter. `provenance.json` records
the verified npm tarball integrity and the runtime's SHA-256 hash.

`DMermaid` and `DMermaidEditor` retain their names because they accept Mermaid
syntax. Pele is their sole rendering engine. No Mermaid runtime, CDN access,
runtime downloads, or new Flutter dependencies are required.

`render.js` calls `pele.render()` with a 1200-pixel layout width, local fonts,
links and images disabled, and explicit source, edge, and SVG limits. It applies
light/dark CSS variables directly to the SVG so they survive standalone image
export, then exports a bounded PNG. Flutter owns display, scrolling, and zoom.
The offline document blocks network resources and navigation. Rendering errors
leave the exact source available in the Native component.

## Verification

Run the focused Flutter checks:

```sh
flutter test test/ui/d_mermaid_test.dart test/plugins/discourse_mermaid/discourse_mermaid_plugin_test.dart test/plugins/discourse_mermaid/mermaid_composer_test.dart test/plugins/discourse_mermaid/pele_compatibility_test.dart
```

Exercise the real production runtime and PNG adapter in both palettes:

```sh
dart run tool/check_pele_renderer.dart
swift tool/check_pele_renderer.swift
```

The Swift runner uses macOS WebKit with a 1-pixel viewport. It writes
`/tmp/pele-check/results-webkit.json` and fails on unexpected results, empty
artwork, or excessive image dimensions. Open `/tmp/pele-check/index.html` in a
browser for visual review. The fixture uses the production Dart document builder
and `test/plugins/discourse_mermaid/fixtures/diagrams.json`.

## Updating

1. Check the Discourse Pele component's version and cooked-markup contract.
2. Fetch that npm version's metadata and tarball. Verify `dist.integrity` before
   extracting the runtime and license. Record integrity and the bundle hash in
   provenance; do not modify the upstream runtime.
3. Update the asset filename in `pubspec.yaml`, `DMermaid`, the packaging test,
   fixture generator, styleguide notes, and this document.
4. Run the focused Flutter checks, static analysis, and the real WebKit fixture.
   Review labels and layout in both palettes. Check supported mobile WebViews
   before raising the JavaScript compatibility baseline.
