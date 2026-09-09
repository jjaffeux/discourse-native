# Button rendered comparison — 2026-09-09

The coordinator granted a browser-only comparison slot while the Mac was locked.
The official [Base UI Button page](https://ui.shadcn.com/docs/components/base/button)
was inspected through CUA Chrome at 1270×847 and 360×700 logical viewports.
The temporary viewport was reset, the original dark theme restored and the
comparison tab closed. No native application was opened or controlled.

## Method and scope

`evidence/button/reference-*.png` are actual browser captures. Their corresponding
`reference-light-metrics.json` and `reference-dark-metrics.json` are read-only DOM
measurements, including bounds, computed typography, padding, colors, borders,
opacity and SVG sizes. Settled focus/hover measurements have separate JSON files.
The frozen Markdown and base-nova registry hashes remain in [button.md](button.md).

`evidence/button/flutter-*.png` are **Flutter widget-test exports**, not native
application screenshots. The exact current public DButton and actual registered
examples were rendered by the macOS platform variant at explicit logical sizes,
then exported using RepaintBoundary.toImage inside tester.runAsync. Export
panels are 640×288 at 100%, or 360×600 at 200%/RTL, with 2× PNG rasterization.
`flutter-metrics.json` records actual rendered bounds and resolved styles.

The reproducible harness is preserved as `evidence/button/export-harness.dart.txt`
and ran as `/private/tmp/button_3a88_render_test.dart` in this checkout. It loads
macOS SFNS, SFArabic fallback and Material Icons explicitly because Flutter's
test font otherwise produces invalid typography/Arabic comparisons. No fonts
are copied into the repository. Neutral samples map the reference's grayscale
palette and 10px radius into the existing tokens; destructive colors use the
reference red values. App samples use the unmodified Light, Dark, Forest and
Plum palette adapters. All captures disable motion so busy states remain legible.

## Measurements and corrections

| Specimen | Live reference | Flutter final export |
| --- | --- | --- |
| Extra Small | 82.21×24, 12/16 text | 82.8×24, 12/16 text |
| Small | 55.76×28, 12.8/22.4 text | 55.8×28, 12.8/22.4 text |
| Default size | 69.98×32, 14/20 text | 70.8×32, 14/20 text |
| Large | 59.42×36, 14/20 text | 60.2×36, 14/20 text |
| Icon sizes | 24/28/32/36px squares | Same four squares |
| New Branch | 121.47×32, 16px SVG, 6px gap | 123.2×32, same SVG/gap |
| Fork | 71.69×32, trailing 16px SVG | 72.0×32, same SVG/placement |
| Default Button | 65.71×32 | 67.1×32 |
| Generating | 114.10×32, 16px spinner | 116.6×32, shared 16px Spinner |

Text-width differences reflect Geist versus the configured native system font;
metrics retain reference size, weight500, leading and border-box spacing. Browser
and Flutter rasterizers are not asserted pixel-identical.

The actual comparison identified and corrected four differences:

1. Small's live computed leading is **22.4px**, not the initially inferred 20px.
   Its surface remains 28px. Vertical padding now represents only the 1px border
   inset, so text may grow naturally at accessibility scales.
2. Dark outline uses the semantic input color (`ColorScheme.outlineVariant`).
   CSS input opacity must be multiplied by the .3/.5 background factor. Replacing
   a translucent token's alpha made the first neutral export too bright; the
   preserved `flutter-before-dark-alpha.png` records this discovered defect.
   The corrected export retains dark subdued outlines and backgrounds.
3. Loading-label leading spinners now receive the same reduced inline padding
   as ordinary leading icons (8px CSS + 1px border inset). The trailing case
   remains mirrored. Regression tests assert both resolved sides.
4. The Size example now uses the reference's vertical group layout below the
   640px preview viewport breakpoint, with 32px group gaps. The 360px live page
   confirmed this behavior. A dedicated Arabic composition was also added,
   including outline, destructive, mirrored trailing arrow, plus and spinner.

## Visual and interaction observations

- All six light and dark variant appearances were inspected on the actual page
  and against final Flutter exports: primary, outline, secondary, ghost,
  destructive and link. The destructive surface is tinted, not solid legacy
  danger. Neutral dark outline brightness now agrees with the source mapping.
- Size examples preserve compact visual heights, square icons, reference artwork
  and row gaps. App targets still expand invisibly on touch platforms; these
  exports use desktop geometry, while dedicated tests cover touch hit regions.
- Original Lucide and Tabler icons reproduce the documented arrow, branch, fork,
  rounded and circular-arrow compositions. Icon source hashes are recorded.
- Generating/Downloading preserve disabled opacity, leading/trailing spinner
  placement and label spacing. The example's extra unavailable state and local
  completion counter are intentional interactive additions.
- Browser pointer hover confirmed muted outline fill, destructive .3 dark fill
  and Link underline with 4px CSS offset. Keyboard traversal exposed the focused
  destructive button. After its .15s transition settled, DOM measurement showed
  a 1px destructive/.4 border plus a 3px destructive/.4 outer ring. Flutter's
  keyboard-focus export shows the corresponding geometry.
- Arabic reference buttons read right-to-left, with the submit arrow pointing
  left. Final Flutter Arabic exports have the same ordering and mirroring.
  SFArabic fallback renders the script correctly; the website uses Noto Sans
  Arabic, so text shapes and widths differ.
- Light, Dark, Forest and Plum exports at 360px, 200%, RTL were visually inspected
  for variant distinction, size groups, rich wrapping, invalid/expanded triggers
  and the Arabic composition. They remain within bounds and preserve readable
  content. The website was not altered to impersonate these custom palettes.

## Verification and remaining gate

After the comparison corrections, **218 focused tests** passed: Button,
reference behavior, all styleguide tests, adoption guard, PollCard and
UserSummary. After adding the exact Arabic example, **11 focused tests** passed.
Root/full-profile analysis is clean. The export harness passes; logs are
`/private/tmp/button-browser-impact.log`,
`/private/tmp/button-browser-final-focused.log`,
`/private/tmp/button-render-final.log`,
`/private/tmp/button-browser-analysis.log` and
`/private/tmp/button-browser-full-analysis.log`.

This completes the **browser-versus-widget-export** comparison only. The actual
macOS production-widget fixture, platform text shaping, native focus/activation
and application rendering still require the coordinator's native slot after
unlock. No spoken VoiceOver, iOS/Linux device run, native screenshot or automated
pixel-diff claim is made. Status remains `in_progress` / `awaiting_slot`.

Existing host adaptations remain: configured palette/font/radius, focus color,
native font underline placement (Flutter has no independent text underline-offset
property), and sRGB state-color interpolation instead of CSS OKLCH mixing.
The last two are explicitly visible limitations, not claims of exact parity.
