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

The ordinary composer presents display equations as flat code-style Math
blocks. Each block contains only its equation preview. Clicking block or inline
math opens its source dialog. Copy source is available when reading rendered
posts. Single-dollar and other inline delimiters stay compact even on their own
line. Source delimiters determine inline/display mathematical mode. Block
selection and keyboard deletion use the host's atomic component behavior. Deleting
a block removes its duplicated paragraph separator
while preserving extra author spacing. Insert always creates a display math
block and supports Shift+M.
Inline math can be typed directly with inline delimiters.
Apply rechecks the complete source and editability, preserves input language
and delimiter notation, and
uses the host transaction/undo history. Cancel never changes the draft.
Nested list/details body editors render math and own their local edit offsets.
Quoted display blocks and links remain source where the enclosing projection
owns the source range; cooking and reading those forms still render math. The host does not provide atomic-node drag/reorder parity.

`DMath` owns exact locally bundled MathJax 4.1.0 and KaTeX 0.16.27. HTML/SVG,
ASCII input, mhchem, copy-tex, safe processing, enriched DOM, and ordered
same-document expression context remain in a live WebView. The plugin maps
labels to keys belonging to the parsed document and routes other allowed links
through the SDK. Neither plugin nor component maintains an equation cache.

The Native MathJax menu is generated from the actual engine menu's finite item
metadata. Native submenus, checkboxes and sliders change the engine's own
renderer, speech, language, braille, explorer, zoom and semantic-export
preferences. Show, Copy, Zoom, Scale, About and Help use Native surfaces.
Upstream-disabled entries remain disabled. These preferences are local to the
expression view and never use browser localStorage. Native horizontal scrolling
retains access to wide expressions. Browser selection does not extend into
Flutter prose; copy-tex applies inside the equation view and Copy source remains
explicit. Device VoiceOver/TalkBack need device verification; enriched DOM is
not evidence of screen-reader parity.

Rendering is bounded to 16,384 units per source expression,
131,072 request units, two million generated HTML units, 16,384 by 4,096 output
points, 16 concurrent engine startups and a 20 second admission/render
timeout. Completed views release startup admission while retaining their interactive
document. Offscreen views retire as the viewport moves. Document context is
kept in order; oversized sibling expressions retain their positions as empty
context, matching error isolation while their own views retain source. A request that exceeds the byte bound retains source rather than
silently dropping macro definitions or references. Oversized, unsupported,
saturated, or rejected expressions retain source. Retired setup finishes before channels, script execution, and documents
are cleared. Settings/source changes replace the isolated view and generation.

Rebuild assets with `npm ci && npm run build` in `tool/math_renderer`. The lock
pins every dependency; `npm run verify` checks the complete asset file set and
hashes. Build copies the complete browser module/font closure,
generates offline speech-map resources, asset entries, and hashes. The exact
speech worker uses bundled map data instead of `file:` fetch, which WKWebView
does not support. No math expression can initiate network requests or navigate
the embedded view. The build does not modify upstream JavaScript distributions.

Run `node tool/math_renderer/fixture.mjs` and
`swift tool/check_pele_renderer.swift /tmp/native-math-check/fixture.html` for
real WKWebView cases. Run the Math source/widget tests and
`node --test packages/discourse_cooking/js/test/math.test.mjs` for focused
behavioral checks.
