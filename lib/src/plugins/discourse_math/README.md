# Discourse Math

The module owns its settings codec, cooked markers, source ranges, authoring
transactions, cooking adapter, and optional Chat preview contribution. It uses
only the public SDK and Native component library. No Math fields are added to
core site configuration or reader/composer controllers.

The cooking parser is the unchanged upstream source at
`96ce8d44401a8a568ecc71561c26dca8ec6bfeb8`. Its hash and revision live in the
cooking provenance manifest. The adapter enables its own feature flags in
restricted Chat profiles. Cooking, including quotes/lists, HTML escaping,
Unicode punctuation, currency, and incomplete multiline blocks, follows that
parser. `vendor.mjs` includes Math in future complete snapshot upgrades.

The ordinary composer renders top-level display equations and inline math.
Native pencil actions open a source dialog. Insert defaults to display on an
otherwise whitespace-only line and supports Shift+M. Apply rechecks the complete
source and editability, preserves input language and delimiter notation, and
uses the host transaction/undo history. Cancel never changes the draft.
Quoted/list block containers and links remain source in the rich editor because
those containers already own the source range. Cooking and reading those forms
still render math. The host does not provide atomic-node drag/reorder parity.

`DMath` owns exact locally bundled MathJax 4.1.0 and KaTeX 0.16.27. HTML/SVG,
ASCII input, mhchem, copy-tex, safe processing, enriched DOM, and ordered
same-document expression context remain in a live WebView. The plugin maps
labels to keys belonging to the parsed document and routes other allowed links
through the SDK. Neither plugin nor component maintains an equation cache.

The Native MathJax menu offers source copy, expansion, available MathML/SVG/
speech/braille exports, output renderer selection, accessibility, and reset.
The browser menu is suppressed. The upstream menu's remaining language,
explorer colour, overflow, keyboard modifier, annotation, scale-all, about/help,
and speech-rule preference submenus are not exposed. This is a Native action
mapping, not complete menu parity. The site zoom setting opens a Native dialog
at 175 percent. Browser engine selection does not extend into Flutter prose;
copy-tex applies within the equation WebView and Copy source remains explicit.
Device VoiceOver/TalkBack and cross-platform platform-view behavior need device
verification; an enriched DOM is not evidence of screen-reader parity.

Rendering is bounded to 16,384 source units, 128 contextual expressions,
131,072 request units, two million generated HTML units, 16,384 by 4,096 output
points, eight live views, 64 queued requests, and a 20 second admission/render
timeout. Oversized, unsupported, saturated, or rejected expressions retain
source. Retired setup finishes before channels, script execution, and documents
are cleared. Settings/source changes replace the isolated view and generation.

Rebuild assets with `npm ci && npm run build` in `tool/math_renderer`. The lock
pins every dependency; build copies the complete browser module/font closure,
generates offline speech-map resources, asset entries, and hashes. The exact
speech worker uses bundled map data instead of `file:` fetch, which WKWebView
does not support. No math expression can initiate network requests or navigate
the embedded view. The build does not modify upstream JavaScript distributions.

Run `node tool/math_renderer/fixture.mjs` and
`swift tool/check_pele_renderer.swift /tmp/native-math-check/fixture.html` for
real WKWebView cases. Run the Math source/widget tests and
`node --test packages/discourse_cooking/js/test/math.test.mjs` for focused
behavioral checks.
