# Accordion reference mapping

Reference frozen on 2026-09-08:

- Documentation: `https://ui.shadcn.com/docs/components/base/accordion.md`
- Frozen Markdown SHA-256: `ccd53e3cb2e6d1cd1cc72588b853fdc8aefe08aab3d5cb515d28dfe09dcf149f`
- Base-nova registry: `https://ui.shadcn.com/r/styles/base-nova/accordion.json`
- Registry SHA-256 inspected 2026-09-09: `01509cb2a91779ee74c2d4a1f75842c0a258bed1758be4f2567af9daabdc39ac`
- Behavior API: `https://base-ui.com/react/components/accordion`

The reproduced frozen sections are Composition, Basic, Multiple, Disabled,
Borders, Card, RTL and API Reference. The implementation is intentionally not
based on Flutter `ExpansionTile`; it composes the accepted `DCollapsible`
interaction, focus-restoration, panel-lifecycle and reduced-motion owner.

## Source-to-Flutter mapping

| Base-nova source | Flutter mapping |
| --- | --- |
| Root `flex w-full flex-col` | `DAccordion<T>` is a stretch-width, minimum-height `Column`. |
| Item `not-last:border-b` | One logical-pixel `DTokens.border` bottom rule except on the final direct child. |
| Trigger `py-2.5 text-sm font-medium` | 10px vertical inset, explicit host-font 14/20 metrics, weight 500, zero tracking; 40px desktop minimum height. |
| `items-start justify-between`, 16px trigger icon | Wrapped heading at logical start and a fixed 16px custom-painted up/down chevron at logical end. |
| `rounded-lg` | Radius is the live host base radius (`lg` = `DTokens.radius × 1`). |
| `hover:underline` | Hover underlines inherited trigger text without adding a Material fill. |
| `focus-visible:border-ring ring-3 ring/50` | One-pixel focus border plus an outside-only three-pixel ring using the live focus color at multiplied 50% alpha. |
| Disabled `pointer-events-none opacity-50` | Trigger remains keyboard/screen-reader discoverable, reports disabled, renders at 50% opacity and cannot activate. |
| Content `overflow-hidden text-sm` | Clipped `DCollapsibleContent` height transition with explicit 14/20 body metrics. |
| Content `pt-0 pb-2.5` | No top inset and 10px bottom inset. |
| Accordion height keyframes | 200ms native height transition; inherited reduced motion makes it immediate. |
| Borders example `rounded-lg border`, item `px-4` | `outlined: true` supplies the live-token border/radius and 16px horizontal item inset. |
| Card example | Actual accepted `DCard`, `DCardHeader`, `DCardTitle`, `DCardDescription` and `DCardContent` composition. |

Touch platforms increase the transparent/empty vertical portion of the trigger
to a 48px minimum without changing its typography or chevron. Large native text
may grow the row and wrap. Directionality controls logical alignment and
chevron placement. Palette, font and radius are resolved during every build, so
live theme changes do not reconstruct the accordion controller or panel state.

## Behavior and lifecycle

- `values` plus `onValuesChange` is controlled state. Without it, the root owns
  an internal `DAccordionController`; an explicitly supplied controller is
  borrowed and remains caller-owned.
- The controller enforces single or multiple expansion and exposes replace,
  open, close and toggle. Reordering stable keyed items preserves state; values
  for removed items are pruned in controller/local modes after the frame.
- Root and item disabled states block user changes. Programmatic controlled or
  controller updates remain possible.
- Base UI's current APG behavior uses ordinary document-order Tab traversal;
  deprecated roving-focus/orientation settings are not reproduced. Enter and
  Space activate through `DCollapsibleTrigger`.
- Closed panels unmount after their exit transition by default. `keepMounted`
  can be inherited from the root or set per panel, retaining fields while
  excluding hidden content from focus, semantics, hit testing and tickers.
- `DAccordionHeader` creates a heading boundary with explicit child nodes.
  Expanded/button semantics remain on the bounded trigger. Interactive panel
  descendants retain independent semantics and focus.
- Browser-only `hidden="until-found"` has no native equivalent. Applications
  can reveal a search match through controlled values or a controller.

## Application audit

No current core or plugin surface is a genuine mutually coordinated accordion
group, so no application migration is made. The Event Composer and Local Dates
advanced panels remain accepted independent `DCollapsible` disclosures. The
Prometheus alert raw-payload panel is also one independent disclosure. Browser
workspace tabs, topic/user filters, settings navigation and nested forum routes
retain their navigation or domain owners; grouping them into an accordion would
change persistence, routing or disclosure semantics.

## Implementation acceptance criteria

- Reproduce all frozen examples with actual public Accordion parts and the
  accepted Card composition.
- Support typed controlled, locally owned and explicitly borrowed-controller
  state in genuine single and multiple modes, including dynamic removal and
  reorder behavior.
- Preserve bounded heading/expanded semantics, independently accessible panel
  descendants, Enter/Space and ordinary Tab behavior, pointer/touch input,
  disabled discoverability and focus restoration.
- Match the recorded geometry, typography, token colors, border, chevron,
  hover, press, focus and motion rules in light, dark and custom themes.
- Preserve state under live palette/font/radius changes, narrow widths, native
  text scaling, RTL and reduced motion; use 48px touch targets without inflating
  desktop artwork.
- Keep generic source independent of Discourse stores, networking, domain state
  and plugin services, and verify Collapsible downstream behavior after the
  narrow focus-painter extension.
