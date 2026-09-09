# Chart: frozen reference mapping and adoption

Reference date: 2026-09-08. Task: `01a08400-ced8-7f22-a1aa-4955c7d28383`.
Branch: `codex/ui-chart`. Status: **in_progress / awaiting native review**.

## Sources and scope

- Official page: https://ui.shadcn.com/docs/components/base/chart
- Markdown and **all inline example source**:
  https://ui.shadcn.com/docs/components/base/chart.md
  SHA256 `c6c51d44c211580548bbce4647965f16458e02c054cb5592aa89405d3b36885d`
  exactly matches the frozen catalogue. No resnapshot or scope change.
- Base Nova registry implementation:
  https://ui.shadcn.com/r/styles/base-nova/chart.json
  SHA256 `c867c2180d6250e8f2883491abd802e1caae65eca6b11af415d42048cec798c5`.
- Raw sources and URL/hash manifest are committed in `reference/chart/`.
  Existing `reference/LICENSE.shadcn.md` supplies the upstream MIT license.
  The Markdown's embedded interactive sample imports new-york-v4; its data and
  composition are reproduced, while reusable content styling follows base-nova.
  Individual base-nova chart example registry URLs return 404; the frozen
  Markdown itself contains the complete executable example source.

The reference deliberately does not wrap Recharts. This port likewise separates
configuration/content from plotting: `DChartContainer` accepts arbitrary child
widgets; `DChartTooltipContent` and `DChartLegendContent` accept typed presentation
payloads. `DBarChart<T>` is the native drawing/focus owner for the documented
bar compositions. No Flutter plotting dependency exists in the original app;
no new dependency, Recharts emulation, or unrelated chart catalogue is added.
All generic chart code lives in `lib/src/ui/components/d_chart.dart`, exported
from `discourse_ui.dart`. `DChartBar` is the reusable inline quantitative mark.

## Frozen section accounting

| Frozen section | Concrete Flutter implementation / example |
| --- | --- |
| Component | Independent configuration scope, plot, tooltip content and legend content. Any custom drawing widget can use the config and content APIs. |
| Updating to Recharts v3 | No JS runtime/version dependency. `initialIndex` is consumed once; a borrowed `DChartController` owns persistent inspection. Plot has explicit bounded width and height; no speculative upstream engine compatibility API. |
| Installation | Public Dart barrel; pinned existing Flutter SDK, no package installation. |
| Your First Chart | Six exact monthly desktop/mobile values, typed accessors, 4px rounded grouped bars. |
| Add a Grid | `grid: true`, horizontal border/50 lines. |
| Add an Axis | `axis: true`, no tick/axis line, 10px tick gap, abbreviated month formatter. Optional value axis for meaningful native edge cases. |
| Add Tooltip | Built-in hover/touch/keyboard inspection; `tooltipBuilder` composes actual `DChartTooltipContent`. |
| Add Legend | `DChartLegendContent` beneath the actual plot. |
| Chart Config | `Map<String, DChartConfigEntry>` provides labels, icon builders and live color resolvers, independent of arbitrary data shape. |
| Theming | Config color callbacks read live `DTokens`/Theme; never cached in state or overlays. |
| CSS Variables | `DChartContainer.of(context).color(context, key)` is the typed scoped variable equivalent. |
| hex, hsl or oklch | Resolved Flutter `Color` values/callbacks replace browser CSS parsing; literal `Color(0xff2563eb)` is supported. No inert CSS-string property. |
| Using Colors / Components | Series falls back to config colors; standalone marks accept resolved colors. |
| Chart Data | `DChartSeries.color(context, datum)` supplies per-datum fills; arbitrary model/value/payload accessors. Browser example uses this path. |
| Tailwind | Ordinary Flutter layout and color properties replace utility class names. |
| Tooltip / Props | `labelKey`, `nameKey`, dot/line/dashed, hideLabel, hideIndicator; labels/values/items are independently formattable. Hidden items are filtered. |
| Tooltip / Colors | Explicit content override, datum color, resolved config color, then live primary fallback. Config icons take precedence over indicators as upstream. |
| Tooltip / Custom | Exact browser/visitors indirection; label and row builders; number formatter. The interactive daily chart uses `nameKey: views`. |
| Legend | Wrapping centered legend; top/bottom spacing, configured icon or color mark; hideIcon substitutes the mark as upstream. |
| Legend / Colors | Datum colors or config callbacks; live changes propagate. |
| Legend / Custom | `nameKey` resolves payload keys, `itemBuilder` replaces an entry. |
| Accessibility | One Tab stop, physical left/right arrows, Home/End, Escape, visible focus, adjustable semantics with current/next/previous descriptions; all categories available even when ticks are skipped. The documentation's one-line LineChart example describes this accessibility capability, not a request to build every Recharts plot family. |
| RTL | Arabic six-month composition, reversed categories and series, directional tooltip/legend/inline marks and physical keyboard mapping. |

There are ten full actual-component examples: five progressive charts,
interactive daily visitors, tooltip treatments, custom content, RTL, and
controlled inspection. The daily data matches the reference April source:
Desktop **7,324**, Mobile **7,250**. Its caption says April because the supplied
source contains April only, despite the reference's “last 3 months” caption.
Usage snippets include self-contained data and the full interactive widget.

## CSS-to-Flutter measurements

Numbers below are source-derived logical pixels at 16px root rem / 100% text.
They are **not** claims of a completed rendered browser comparison.

| Reference geometry | Native mapping |
| --- | --- |
| `text-xs` | `DiscourseTypography.xs` = 12px; base 16px leading, weight 400, zero tracking, host font family. Tooltip row names/values use leading-none = 12px. Values use monospace/tabular figures and weight 500; labels weight 500. |
| Chart measured dimensions | Explicit native plot height 200px, daily plot 250px, responsive bounded width. Native chart minimum retains 120px drawing space when axis text grows; empty data still measures. The first two examples use 16:9 with a 200px minimum; explicit-size steps use 200px. |
| Bar groups | Default 10% category margin each side, 4px inter-series gap (reduced only when groups cannot fit), all-corner 4px explicit bar radius; 5px plot margin. These are plotting geometry, not host CSS rounded-class tokens. Daily bars use radius 0. |
| Grid | Five horizontal tick positions, 1px strokes, `tokens.border` with **existing alpha multiplied by .5**. Rounded upper positive domain, zero/negative/missing input handled explicitly. |
| Axis | Muted foreground; no baseline/tick strokes; 10px gap. Colliding labels skip at narrow/high-scale sizes and may ellipsize; full values remain inspectable. |
| Tooltip | 128px minimum width, intrinsic preferred width capped at available width/220px, 10px horizontal and 6px vertical padding, 6px gaps, 1px border with multiplied .5 alpha. |
| `rounded-lg` tooltip | `tokens.radius × 1` (verified proportional scale). |
| Tooltip shadow-xl | Black .1 alpha, (0,20)/25 blur/-5 spread and (0,8)/10 blur/-6 spread. Explicit shadow color is a lighting effect, not a hardcoded theme swatch. |
| Dot / line / dashed | 10×10px dot with 2px corners; 4px line stretched to row/nested-label height; 3px dashed stroke, 3px dash/3px gap. |
| Tooltip icons | 10px icon theme; muted foreground. |
| Legend | 8×8px/2px-radius marks; 12px icons; 6px item gap, 16px between entries; 12px above bottom legend or below top legend. Native wrap adds 6px between lines. |
| Interactive header | Native layout breakpoint 640px, split title/total columns, 24/32px horizontal and 16/24px vertical total padding, 12px label, 18/30px bold total with leading 1, border separators and muted × .5 selected background. Reuses existing DButton's native interaction owner. |
| Input token | Not used: Chart has no text input. No `border`/`input` substitution. |

## Interaction and native adaptations

- `DChartController` is an optional borrowed `ValueNotifier<int?>`. Owned
  controllers consume `initialIndex` once and are disposed; borrowed controllers
  and focus nodes survive replacement/removal. Invalid indexes hide inspection,
  including when a dataset shrinks, without mutating caller state during build.
- Mouse hover, click, touch and horizontal drag share category geometry. Keyboard
  enters through one focus stop; modified shortcuts bubble. Escape clears
  inspection. Clicking outside clears inspection through native TapRegion.
- Tooltip is constrained within the chart rather than using a global web/SVG
  portal. Overflowing tooltip content can scroll. Custom tooltip content is
  display content; interactive app controls belong outside the plot. Explicit
  semantics expose values without requiring tooltip hit-testing.
- Flutter's text scaler is the sole owner of accessible font scaling. Legend
  entries wrap, axes retain plot space, and values remain available through
  inspection. No animation/controller clock is added, honoring reduced motion.
- Chart inspection is not editable domain input; Form save/validation/reset is
  not applicable. Callers may include the chart in a Form without adding a fake
  field or changing the form's state.
- Config callbacks support explicit light/dark branches and all host palette
  changes. The examples use host primary/tertiary in place of reference blue or
  chart-1/chart-2 swatches. The supplied palette takes precedence as required.
- Generic grid/cursor styling covers the documented bar owner. Polar/radial/
  reference-line CSS selectors in the registry are renderer-specific styling;
  there are no exposed but unimplemented polar or line-plot APIs.

## Adoption audit

Search covered all core shell renderers and every bundled plugin: Assign, Chat,
AI, Events, GitHub, Lazy Videos, GIFs, Local Dates, Poll, Prometheus, Reactions,
and Voice. There was no plotting package or general chart renderer.

- **PollCard:** removed `_ResultBar`; visible option rows now use `DChartBar`.
  Percent calculation, multiple-choice rounding, numeric averages, confidential
  missing counts, ranked-choice display, async success/error/accepted-result
  handling, voting/withdrawal guards, permissions and expiry timers are unchanged.
  The 7px height is retained; bar corners now use the explicit 4px chart mark
  radius and live muted track. RTL fills from the directional start.
- **UsersPage `_MetricCell`:** replaced its private fraction/decorated bar with
  `DChartBar`, retaining `max(.06, intensity)`, 64% cell-content height, 4px corners,
  numeric overlay, per-column maxima, value parsing, synchronized scroll owners,
  width persistence and every callback. Existing alpha now multiplies palette
  alpha. No shell data or normalization entered the generic component.
- **Retained:** progress/loading indicators in core, Events, Assign and Chat are
  task progress, not charts. Topic progress remains navigation. Skeleton
  fractional blocks remain Skeleton. User summary statistics are text/card
  composition, not plots. Prometheus renders alert tables; Voice diagnostics
  render text/statistic fields. Existing ranked-choice result ordering and pie
  markup's accessible option tallies remain Poll's native domain adaptation;
  replacing them with a speculative pie renderer is outside this Chart scope.
- Adjacent Poll Button/Checkbox/Radio and editor Switch changes remain in their
  other component tasks. No unmerged dependency was imported. Coordinator will
  reconcile shared files during serialized integration.

`lib/chart_review_main.dart` mounts **actual** PollCard and UsersPage widgets,
with ready/empty/confidential/pending/error controls, a memory-only directory
width persistence adapter, no app stores/accounts/network, plus the actual
interactive chart and a styleguide route. Native inspection remains pending.

## Verification / remaining gate

Focused commands and final source/build provenance are in `chart-native.md` and
this component's progress row. Root/full profiles retain Flutter 3.47.2 and all
lockfiles. Tests verify behavior and image rendering, not device or pixel parity.
The locked Mac has not been operated. Browser/reference/native styleguide and
production-fixture comparison still require the coordinator's explicit slot;
status remains in_progress, examples baseline, and the branch is not mergeable.
