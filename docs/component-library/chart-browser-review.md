# Chart rendered reference comparison

Compared the official Base UI Chart page to font-loaded Flutter exports of all ten registered examples and actual PollCard/UsersPage fixtures on 2026-09-09. Browser-only slot released after restoring dark theme, resetting viewport and closing owned tab 1360425196. No native application launched. Status remains **in_progress / awaiting_slot** for native review.

Evidence lives in `reference/chart/browser-review/`: full browser screenshots (light/dark, daily desktop/mobile, tooltip anatomy and narrow RTL), DOM measurement JSON, actual Flutter PNGs/text metrics and a SHA256 manifest. Frozen source snapshots remain unchanged. `font-sources.json` records the actual reference font URLs and hashes. Font files were downloaded solely for the export harness and converted with fontTools; app fonts, packages and pins are unchanged. Reproduce with those fonts in `/tmp/chart-browser-evidence/fonts/{Geist,GeistMono,NotoSansArabic}.ttf`, then `flutter test --no-pub tool/chart_visual_export.dart`.

| Observation | Correction / measured result |
| --- | --- |
| Monthly source domain 0–320; first value 186 | Five nice ticks now produce 320 instead of 400. |
| Source monthly footprint 509 × 286.3125 | All progressive examples use 16:9/minimum 200; legend occupies 28 inside total height. Flutter raster export rounds total to 287. |
| Plot margins 5; grouped bars 31 wide, gap 4, radius 4 | Removed focus-border layout inset; floor whole-pixel bar widths and retain fractional bars in very narrow layouts. |
| Legend plot height 218; first bar 126.7129 | Legend reservation now matches source; fractional Flutter layout differs by less than .313 px. |
| Tooltip 128 × 66, padding 10/6, row gap 6, marks 10 | Intrinsic content now stays compact; values align at row end; pointer anchor uses category center plus 10 with collision handling. Line 4, dashed 3. |
| Daily source header 98, total footprint 437 | Native wide header and vertical plotting gaps corrected. Title 15px/15 weight600; total values30px weight700. |
| Daily total text widths 78.72656/80.70312 | Loaded Geist Flutter widths 78.71983/80.6998; measured totals determine header widths. |
| Daily labels Apr2,6,10,14,18,22,26,30 | Gap32 and whole-chart edge bounds reproduce tick selection at matched plotting width. |
| RTL reverses categories only | Series retain source order inside each category. Arabic labels use three-character abbreviations; narrow reference width245 captured and compared. |
| Escape after dismissal | First Escape clears valid inspection; second bubbles to parent. Invalid borrowed index also bubbles without rewriting controller. Regression test added. |

The reference card is 638px wide and the native wide fixture 640px; the native breakpoint uses component width. Narrow large-text totals stack to avoid clipping. Tooltip anatomy uses native wrapping examples and descriptive text rather than the documentation's decorative annotation arrows; line tooltip has 144px width to preserve the title. Native focus rings, accessible inspection and constrained tooltip scrolling are platform adaptations. The daily caption accurately names April, matching the supplied data.

Exports include real PollCard 70/30 percent result bars (7px) and UsersPage full/half maximum bars with visible numeric overlays, in both themes. They use production palettes; isolated reference examples use reference colors for comparison. This is rendered browser-to-Flutter evidence, not native macOS, VoiceOver, touch-device or pixel-identical raster verification. Native acceptance remains pending.
