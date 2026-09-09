# Scroll Area browser / widget-export comparison

2026-09-09. Coordinator granted the browser-only slot. Used one task-created
Chrome tab at https://ui.shadcn.com/docs/components/base/scroll-area. Inspected
actual Base UI/base-nova Tags, Horizontal and Arabic RTL, dark/light, focused
keyboard Home/End and a temporary 360px viewport. Restored the original dark
theme, reset viewport override, closed only that tab and explicitly reported
browser RELEASED before final checks/builds. No native app was launched.

## Evidence and measured corrections

Committed screenshots and metrics: reference/scroll-area/rendered. manifest.json
records every artifact SHA256 plus local font hashes. Existing sources.json
retains exact primary registry/documentation/Base UI source and artwork URLs.

| Property | Browser measured | Flutter after correction |
| --- | --- | --- |
| Tags outer / viewport | 192×288 / 190×286 | Same border-box sizes |
| Vertical track / thumb | 10px / 7px, trailing inset 1px | RawScrollbar 7px with 1px inset |
| Tags initial thumb | 42.4766px, 286px viewport, 1912px content | Same proportional native geometry and 37px row pitch |
| Heading / rows | 14/14 weight500; 14/20, 16px heading gap | Explicit same metrics; host font retained |
| Rounded-md | 8px at base10 | Corrected to base×0.8 for reference examples and inherited viewport |
| Horizontal outer | 384×258 | Corrected to same intrinsic example height |
| Photos | 150×200 visible; HTML attributes300×400 | Corrected prior300×400 display to150×200; same artwork |
| Focus | 3px exterior ring at50%; outline-style:none | drawDRRect outside-only band, no opaque outline, alpha multiplication |

The initial source-only implementation doubled the visible photo dimensions,
used the full host radius for rounded-md, and spread a BoxShadow behind the
transparent focused viewport. Those differences are fixed. The ring regression
reads actual RGBA pixels: interior and beyond-ring pixels remain unchanged,
while a50%-alpha red token with the50% ring modifier produces a25% blend.

## Render exports inspected

`flutter test --no-pub tool/scroll_area_render_test.dart` exports the actual
registered five examples via componentExamples and the actual production
widgets mounted by ScrollAreaReviewApp. It explicitly loads SFNS, SFArabic,
MaterialIcons and bundled JetBrains Mono; proprietary local font bytes are not
copied into the repository. SFNS is used for the Roboto/system family aliases in
the test engine, and an explicit Arabic fallback is supplied through the host
text theme. This avoids Ahem and missing Arabic glyphs; it is not a native font
selection test. Reference uses Geist, so glyph widths/antialiasing differ from
the intentionally retained host font. Caption width slightly changes the exact
horizontal thumb length; visual thickness, inset, radius and content pitch agree.

Inspected light/dark examples, base10 green custom-token examples, transparent
focus before/after, and360px/200% RTL examples. The Tags list wraps long version
text at200%; the horizontal artwork retains150×200 bounds and grows captions.
The custom palette keeps the scroll thumb/ring semantic colors and8px md radius.
Host light canvas is gray-blue and dark canvas slightly lighter than the website;
these are host palette differences, not invented component backgrounds.

Production exports include Sidebar content, CodeBlock, Prometheus AlertTables,
EventCalendar, Assign people rail, DiagnosticsPanel and VoiceDiagnosticsView in
ordinary light, green custom tokens, and360px/200%. The fixture's Sidebar uses
public noncollapsible mode so its actual scroll content remains available at
narrow widths; this does not change production Sidebar behavior. Reviewed the
bounded thumbs on their existing viewport edges and preserved content layouts.

## Remaining differences / limits

- At360px/200%, pre-existing DiagnosticsPanel fixed-height row Columns at lines
  851 and876 overflow vertically by14px. The render export records14 layout
  exceptions in fixture-render-errors.json; reported to the coordinator.
  No generic Scroll Area layout causes or fixes those row-height constraints.
- At narrow large text the calendar weekday headings crowd each other and Assign
  member labels truncate in its existing grid. These retained app layouts are
  visible in the exports; they were not restyled as part of Scroll Area.
- The export engine does not load the native color-emoji font: AlertTables' flame
  is a missing-glyph mark in exports. Native emoji rendering remains unverified.
- The diagnostic fixture uses local callbacks and in-memory data. It verifies
  rendering of the real widgets, not authenticated production state or platform
  services. Some large-text long content extends below the captured window and
  remains in its existing scroll owner.
- No native trackpad, VoiceOver, device, or pixel-parity claim is made from this
  browser/render pass. The later isolated macOS acceptance is recorded in
  scroll-area-native.md.

The export runner reports fixture rendering errors explicitly as artifacts;
its success is not a claim that every production large-text layout passed.
The normal focused regression suite remains the acceptance test for this change.
