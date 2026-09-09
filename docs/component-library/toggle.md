# Toggle reference mapping

Frozen reference date: 2026-09-08. Source inspection: 2026-09-09.

## Sources

- Documentation: https://ui.shadcn.com/docs/components/base/toggle
- Frozen Markdown: https://ui.shadcn.com/docs/components/base/toggle.md
- Frozen Markdown SHA-256: `df0f3e67987ad00fc40be86458c43a330126f3babfd31134644c7fc0284ec7cc` (verified exactly)
- Registry: https://ui.shadcn.com/r/styles/base-nova/toggle.json
- Behavior API: https://base-ui.com/react/components/toggle.md

The registry source was inspected directly. It declares the default and outline
variants, default/sm/lg sizes, pressed and disabled states, and Base UI's
controlled `pressed` / uncontrolled `defaultPressed` ownership.

## Reference-to-Flutter mapping

CSS pixels map one-to-one to Flutter logical pixels at 100% text scale.

| base-nova source | `DToggle` |
| --- | --- |
| `h-7/8/9`, `min-w-7/8/9` | 28/32/36px minimum visual size for small/regular/large |
| `px-2.5`, `gap-1` | 10px logical horizontal padding and 4px icon gap |
| `text-[.8rem]`, `text-sm`, `font-medium` | 12.8px small or 14px regular/large, host family, weight 500 |
| default 16px SVG; small 14px SVG | `IconTheme` at 16px or 14px |
| `rounded-lg`; small `min(radius-md,12px)` | host radius; small `min(.8 × host radius, 12px)` |
| transparent default and outline surface | transparent resting surface |
| `border-input` | `DTokens.colors.outlineVariant` |
| `hover:bg-muted`, `aria-pressed:bg-muted` | `DTokens.muted` on hover, pointer press and toggled-on |
| `focus-visible:border-ring`, 3px `ring/50` | focus-token 1px border plus outside-only 3px half-alpha ring |
| destructive invalid border/ring 20% light, 40% dark | `DTokens.destructive`, multiplying existing alpha |
| `disabled:opacity-50` | whole-control 50% opacity and no pointer/keyboard activation |

Desktop targets remain as compact as the reference. iOS/Android targets are at
least 48×48 while keeping the visual surface compact. Large text can grow the
surface rather than clipping; narrow widths ellipsize the one-line label. RTL
uses directional icon placement. MediaQuery reduced motion makes transitions
immediate. Palette, font and radius are read on every build so live theme
changes do not replace controlled or internally owned state.

## App adoption boundary

Independent mute, deafen, camera, screen-sharing, raise-hand and recording
states in Voice are suitable controlled toggles; their controllers retain all
async and domain ownership. Momentary composer mark commands are not converted
because they transform a selection and do not own a persistent independent
on/off value. Gallery grid/carousel controls are mutually exclusive and remain
for Toggle Group/Tabs. Menu, navigation and dialog launch actions remain
buttons. Presence and proofreading settings retain their row/switch
composition, which is more appropriate than a compact toggle button.

## Native adaptations

- Touch hit targets expand invisibly to 48px; the base-nova artwork does not.
- Flutter `Semantics(toggled:)`, focus traversal and Space/Enter activation map
  native button behavior to Base UI's `aria-pressed` contract.
- The app's configured font and semantic palette replace Geist and fixed web
  colors. Geometry, weight, leading and relative radius remain explicit.
