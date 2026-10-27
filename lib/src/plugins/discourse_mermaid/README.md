# Mermaid and Pele compatibility

`discourse-mermaid` is a bundled native plugin with cooked-element and composer
toolbar capabilities. It has no server requests, session state, or dependencies
on other plugins. Discourse distributes the web integration as a theme
component; native installs this module through its plugin manifest.

This module also supports [Discourse Pele](https://meta.discourse.org/t/discourse-pele/415914).
Pele uses the same `mermaid` fences and server-cooked markup as Discourse
Mermaid. Its [initializer at
8cd113d57122f00dfefb145344c02f78d9ba014c](https://github.com/discourse/discourse-pele-theme-component/blob/8cd113d57122f00dfefb145344c02f78d9ba014c/javascripts/discourse/api-initializers/discourse-pele.js)
decorates `pre[data-code-wrap=mermaid] > code` in posts and chat. The
`pele-wrapper` is added by the web client and is not part of the server response.
Native therefore needs no separate module, installation detection, or server API
for Pele. Existing diagrams and the composer action work on either kind of site.
The Native kit's `DMermaid` and `DMermaidEditor` use bundled Pele 1.10.0 for
rendering on every site, including sites using the older Mermaid component.
The component names and composer fences continue to describe the Mermaid syntax.

The compatibility baseline is the [upstream initializer at
b5d31a95e442d754df9300688afaa111e9e333dd](https://github.com/discourse/discourse-mermaid-theme-component/blob/b5d31a95e442d754df9300688afaa111e9e333dd/javascripts/discourse/api-initializers/discourse-mermaid-theme-component.js).
The cooked marker was also checked against the [Discourse Mermaid
topic](https://meta.discourse.org/t/discourse-mermaid/218242).

## Behavior

- Recognizes `pre[data-code-wrap="mermaid"]` containing nonempty `code` text,
  preserving decoded whitespace and entities. It uses the shared cooked-element
  hook wherever the host enables plugin rendering, including posts and previews.
  Plain language-tagged code without the marker stays with the core renderer.
- Honors positive finite `data-code-height` values, bounded to 80–1200 pixels.
- Uses the Native kit's `DMermaid` for light/dark artwork, an expanded pan/zoom
  dialog, source inspection, and copying. Inline images leave scrolling to the
  post. Expanded diagrams support pinch/drag, zoom/fit buttons, and arrow-key
  panning when focused. Source remains left-to-right in RTL layouts.
- Adds **Mermaid chart** to the composer toolbar. It inserts a fenced sample
  through the editor host and respects loading, submission, and stale-editor
  admission. The server still cooks the submitted Markdown.

## Renderer and limits

`DMermaid` bundles Pele 1.10.0 and uses the existing `webview_all` platform
support. A temporary 1-pixel local WebView renders with a 1200-pixel layout
width, exports a PNG, then unloads its document and removes the JavaScript
channel. Flutter owns the displayed image and interactions. No site URL, cookies,
API key, or post text is sent to a rendering service.

The document blocks network resources and navigation. Pele renders SVG labels
with links and external images disabled and explicit resource limits. Light/dark
CSS variables travel with the exported SVG. Diagrams requiring unavailable
external assets may omit those assets. Errors retain readable/copyable source.
Diagram fonts scale with zoom;
the surrounding Native controls follow the app's text scale.

Source is limited to 50,000 UTF-16 code units, flowcharts to 500 edges, rendering
to 20 seconds, and output to 4096 pixels per axis and four million total pixels.
The memory-only cache holds at most 12 diagrams and 16 MB of encoded images.
Bundled source, license, integrity, and update notes live in
[`ui/assets/pele`](../../ui/assets/pele/README.md).

## Verification

`pele_compatibility_test.dart` checks the cooked diagram captured from the Pele
announcement and cooks its fenced sample through both post and chat profiles.
It verifies the default bundled manifest renders both server and offline HTML
through `DMermaid`, preserving the source without site or theme metadata.

The plugin tests cover the actual cooked marker, decoded source, malformed
input, bounded height, isolated installation/core fallback, and composer edits.
The widget tests cover bundled assets, document escaping, network/navigation
policy, rendering callbacks, stale renders, cleanup, timeout, malformed output,
source/copy actions, zoom/fit/keyboard panning, and narrow RTL/large-text layouts.

`dart run tool/check_pele_renderer.dart` writes an offline browser fixture to
`/tmp/pele-check/index.html`. Open it for visual review, or run
`swift tool/check_pele_renderer.swift` to verify the real runtime, production
document, and PNG export in macOS WebKit with a 1-pixel viewport. It checks the
authored diagram corpus in both palettes, including invalid syntax and attempted
frontmatter security overrides. Mobile devices require separate validation.
