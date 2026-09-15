# Bundled Mermaid runtime

`mermaid-11.15.0.min.js` is the unmodified `dist/mermaid.min.js` from the official
[`mermaid` npm package](https://www.npmjs.com/package/mermaid/v/11.15.0).
The package's MIT `LICENSE` is bundled and registered with Flutter's license
registry. `provenance.json` records the npm tarball, verified SHA-512 integrity,
bundle SHA-256, and corresponding Discourse compatibility commit.

`render.js` is the native adapter. It selects strict security and SVG labels,
renders in a fixed measurement container, and exports a bounded PNG. Mermaid
11.15 needs small SVG-label accommodations: circle mindmap labels need a center
text anchor, Journey text needs the active theme's text color, and Journey/C4
must explicitly select SVG text placement. The upstream bundle is unchanged.

## Updating

1. Check the Discourse Mermaid initializer and renderer for changes to cooked
   markers, syntax, theme settings, and runtime version.
2. Fetch the chosen version's metadata and tarball from `registry.npmjs.org`.
   Verify the complete tarball against `dist.integrity` before extracting the
   runtime and license. Record the new integrity and bundle hash in provenance.
3. Update the filenames and version references in `pubspec.yaml`, `DMermaid`,
   the asset test, styleguide notes, browser fixture generator, and plugin notes.
4. Recheck each SVG-label accommodation against the new renderer. Run the
   plugin/widget tests, static analysis, and `tool/check_mermaid_renderer.dart`.
   Review actual images in both palettes and in the native review fixture;
   successful parsing alone does not guarantee readable labels or layout.

No CDN or runtime download is used. This adds about 3.3 MB of uncompressed
JavaScript to the application assets and no new Flutter dependency.
