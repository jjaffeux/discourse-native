# Mermaid plugin

`discourse-mermaid` is a bundled native plugin with cooked-element and composer
toolbar capabilities. It has no server requests, session state, or dependencies
on other plugins. Discourse distributes the web integration as a theme
component; native installs this module through its plugin manifest.

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

`DMermaid` bundles Mermaid 11.15.0 and uses the existing `webview_all` platform
support. A temporary 1-pixel local WebView renders into a 1200-pixel measurement
container, exports a PNG, then unloads its document and removes the JavaScript
channel. Flutter owns the displayed image and interactions. No site URL, cookies,
API key, or post text is sent to a rendering service.

The document blocks network resources and navigation, enables strict Mermaid
security, and prevents author overrides of security and resource limits. SVG
labels replace HTML labels, and diagram links are inactive. Diagrams requiring
remaining HTML labels or unavailable external assets may fail or omit those
assets. Errors retain readable/copyable source. Diagram fonts scale with zoom;
the surrounding Native controls follow the app's text scale.

Source is limited to 50,000 UTF-16 code units, flowcharts to 500 edges, rendering
to 20 seconds, and output to 4096 pixels per axis and four million total pixels.
The memory-only cache holds at most 12 diagrams and 16 MB of encoded images.
Bundled source, license, integrity, and update notes live in
[`ui/assets/mermaid`](../../ui/assets/mermaid/README.md).

## Verification

The plugin tests cover the actual cooked marker, decoded source, malformed
input, bounded height, isolated installation/core fallback, and composer edits.
The widget tests cover bundled assets, document escaping, network/navigation
policy, rendering callbacks, stale renders, cleanup, timeout, malformed output,
source/copy actions, zoom/fit/keyboard panning, and narrow RTL/large-text layouts.

`dart run tool/check_mermaid_renderer.dart` writes an offline browser fixture to
`/tmp/mermaid-check/index.html`. Serve that directory on a loopback HTTP port and
open it in a browser. It exercises the production document, runtime, and PNG
renderer in a 1-pixel iframe, including the width-dependent Gantt layout. All
46 cases passed (23 inputs in both palettes), including syntax errors and
attempted frontmatter security overrides. Inputs are authored compatibility
examples in `test/plugins/discourse_mermaid/fixtures/diagrams.json`.

`tool/mermaid_review_main.dart` exercises the production cooked renderer and
opens the actual component styleguide. macOS review covered flowcharts,
sequences, markdown/Unicode labels, source actions, expansion/zoom/fit, and a
320-pixel column with 200% text and RTL. The final Gantt container correction
was verified in the 1-pixel browser fixture and a successful macOS build; the
Mac locked before its final native visual recheck. iOS and Linux were not
device-tested.

The 183 focused renderer, plugin, manifest/boundary, packaging, and control
tests passed, and `flutter analyze --no-pub` was clean. Five broader styleguide
tests also fail with Mermaid registration removed: theme/viewport persistence,
Accordion preview height, Direction persistence, Typography persistence, and
Sidebar mobile selection. Those existing failures are outside this change.
