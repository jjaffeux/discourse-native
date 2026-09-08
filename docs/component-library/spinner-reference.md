# Spinner visual mapping

The frozen Spinner sections and catalogue remain unchanged. Source inspection
on 2026-09-08 supplements that snapshot with the official
[base-nova registry](https://ui.shadcn.com/r/styles/base-nova/spinner.json),
[rendered documentation](https://ui.shadcn.com/docs/components/base/spinner),
[Lucide loader-circle SVG](https://github.com/lucide-icons/lucide/blob/main/icons/loader-circle.svg),
and [Tailwind animation definition](https://github.com/tailwindlabs/tailwindcss/blob/main/packages/tailwindcss/theme.css).
The registry's `Loader2Icon` resolves to the exact `loader-circle` path visible
in the documentation's rendered SVG. The customization section uses Lucide
[LoaderIcon](https://github.com/lucide-icons/lucide/blob/main/icons/loader.svg).

SHA-256 fingerprints below identify the exact source bytes captured on
2026-09-08, including the registry JSON formatting. The checked-in SVG test
fixture is byte-identical to the captured Lucide loader-circle source.

| Captured source | SHA-256 |
| --- | --- |
| [Spinner registry](https://ui.shadcn.com/r/styles/base-nova/spinner.json) | `d949d0b91ff34620eecf2bb359536fd3e6942b518dc0a396b77fd02a90661b61` |
| [Lucide loader-circle](https://raw.githubusercontent.com/lucide-icons/lucide/main/icons/loader-circle.svg) | `043021bb903919668804bdb6fee0342072e4ffea5f03fbd857774c440179ad3b` |
| [Lucide LoaderIcon](https://raw.githubusercontent.com/lucide-icons/lucide/main/icons/loader.svg) | `54b6eeae749a70379df86e6360670a838d0f98f00d5a887d50bd76ca62cbf0d4` |
| [Tailwind animation source](https://raw.githubusercontent.com/tailwindlabs/tailwindcss/main/packages/tailwindcss/theme.css) | `443d7af364200f8ec8352dc78e39485a118a1840d498c97967bf0ae402b39167` |
| [Button registry](https://ui.shadcn.com/r/styles/base-nova/button.json) | `9ba7e870178813f0552b818a913a2792fb500c779e36395740b4973e3025d427` |
| [Badge registry](https://ui.shadcn.com/r/styles/base-nova/badge.json) | `ccc20021cdcbf0fb23c0d4d28f1da4adde8e51ba59f4b11dd2722ed97a5ee3a4` |
| [Input-Group registry](https://ui.shadcn.com/r/styles/base-nova/input-group.json) | `acf9c5497a6c844dee87fbd4afefb6cd8be9ce50d050d14d58a340d955e517a1` |
| [Empty registry](https://ui.shadcn.com/r/styles/base-nova/empty.json) | `e89ffe0fc2969956f6e1d601bd3f00b068600ac08e31590f65344e79ff242230` |
| [Item registry](https://ui.shadcn.com/r/styles/base-nova/item.json) | `eb7167bffffb69a5e808fec2a80923fbf80f594d2f942efa2da1a605fdfd87b7` |

| Reference | Flutter mapping |
| --- | --- |
| `size-4` | `DSpinner()` occupies a 16×16 logical-pixel box. Sizes 12, 16, 24 and 32 reproduce `size-3/4/6/8`; callers can supply any positive size. |
| Lucide `viewBox="0 0 24 24"`, path `M21 12a9 9 0 1 1-6.219-8.56` | The same SVG path and view box, using the app's existing `flutter_svg` renderer on every platform. No platform-specific replacement artwork. |
| No fill; currentColor; 2-unit rounded stroke/caps/joins | Inherited icon color, then the current theme foreground; explicit color overrides it. `strokeWidth` is in SVG view-box units and scales with size (the 16px default has a 1⅓px stroke). |
| `animate-spin`: 1s linear infinite, 360° clockwise | `DMotion.spin` and a linear `RotationTransition`, unchanged by RTL. |
| Size example: 24px gaps | `Wrap(spacing: DSpacing.xl)` preserves 24px gaps and wraps when needed. |
| Customization: eight radial strokes | The exact LoaderIcon SVG is supplied as the example's custom child. Other arbitrary artwork is also supported and fitted to the requested box. |
| Button example: default/outline/secondary, disabled, small size | Three disabled reference compositions use the actual DButton with local sample theming: 28px visual height at 100% text, 12.8px/20px text, 16px spinner, 4px gap, 6px start inset and 10px end inset, 50% disabled opacity. Separate action controls demonstrate the existing app DButton's async ownership. Its loading slot now uses the 16px Spinner default. |
| Badge: 20px height, pill, 12px text and icon, 4px gap | Local badges use a 32px pill radius, theme primary/secondary/outline roles, 12px/16px label text, 12px DSpinner, 4px gap and 6px/8px directional insets. Height grows with text scaling. |
| Input Group: 448px maximum width, 16px gaps; 32px single line; 16px inline/block icons | Local bordered groups use a borderless native TextField for editing, 14px text, reference padding and muted status color. The textarea footer holds the 16px Spinner, 8px gap and send action. Initial examples show disabled validation; accepting/rejecting restores editing. |
| Empty: 24px outer padding; 32px muted media box with 16px spinner; 14px title/description | Local composition uses those dimensions, 16px media-to-title and content gaps, 8px title-to-description gap, relaxed muted description and a small Cancel action. Completion/cancellation/error controls preserve the same example state owner. |
| Item overview/RTL: max-width 320px, muted/50, 12px horizontal and 10px vertical padding, 10px gaps | Payment example uses these values, a 16px leading Spinner and tabular amount at its intrinsic width, capped at half the row for large text; direction selects English or Arabic and logical positioning. |
| `role=status`, loading label | One native loading-spinner semantic role with a localizable live label; decorative child artwork is excluded. A containing control can own the status through `semanticLabel: null`. |

The companion dimensions were checked against the official
[Button](https://ui.shadcn.com/r/styles/base-nova/button.json),
[Badge](https://ui.shadcn.com/r/styles/base-nova/badge.json),
[Input Group](https://ui.shadcn.com/r/styles/base-nova/input-group.json),
[Empty](https://ui.shadcn.com/r/styles/base-nova/empty.json), and
[Item](https://ui.shadcn.com/r/styles/base-nova/item.json) registry sources.
These private sample compositions do not introduce additional public component
APIs; their catalogue tasks retain ownership of those components.

The concrete adaptations retain the original app requirements: semantic colors
come from the active site palette, rounded rectangular surfaces use its radius,
and text keeps the host font family. Large text can increase badge/input/button
height and wrap the payment title instead of clipping essential status text.
Reduced motion, disabled ticker subtrees and inactive apps pause rotation while
keeping the busy state. Native editing, keyboard focus and loading-button
semantics remain owned by Flutter and DButton.

The independent SVG fixture in `test/fixtures/spinner/loader-circle.svg` is
rasterized and compared exactly with the rendered DSpinner in the component
test. Native inspection outcomes, remaining checks and the bounded forced-semantics
comparison are recorded in [spinner-native.md](spinner-native.md) and the Spinner
progress row. Lucide and Feather
attribution is preserved in [licenses/lucide.txt](../../licenses/lucide.txt).
