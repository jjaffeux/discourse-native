# Dashboard chart tones, mockup parity

Reference: `test-mobile-layout` at `9b59748` (`--chart-1` to `--chart-5` in
`mock_app.css`, `DASH_TONES` and `DASH_TRAFFIC` in `App.tsx`).

## The scale

`DChartTone` (`lib/src/ui/components/d_chart.dart`) is the kit's one chart
palette. It replaces `DChartColors.series`, whose tertiary/secondary roles and
background lerps were a different rule, and every caller was migrated.
Each step is derived from the live palette, so a host accent or a dark scheme
moves it. `panel` is `DTokens.panelBackground`, the opaque panel.

| Step | Mockup | Rule |
| --- | --- | --- |
| `strong` | `--chart-1` | the accent |
| `mid` | `--chart-2` | accent 62% over the panel |
| `pale` | `--chart-3` | accent 32% over the panel; dark scheme: accent 30% over the text |
| `muted` | `--chart-4` | quiet text 62% over the panel |
| `faint` | `--chart-5` | quiet text 34% over the panel (was 38%) |

`DChartTone.at(index)` hands out the steps in order, starting over past the
fifth, for series that have no meaning of their own.

## Where it is used

- Site traffic stacks by kind: logged in `strong`, anonymous `mid`, other
  (likely crawlers) `muted`, crawlers `faint`, the mockup's order. An id the
  app does not know takes `DChartTone.at(index)`. The mockup's `pale`
  (embedded pageviews) has no counterpart in the payload the app reads.
- The mockup's "Who's posting?" three-series split has no dashboard
  counterpart in the app, so nothing maps to it.
- Report charts (`report_page.dart`) colour series by position with
  `DChartTone.at`, so the first series is the accent and the legend order is
  the traffic order.
- Report cards' `--dash-tone` sheen follows the change's good/bad tone, as in
  the mockup; cards without one use `strong` (the mockup's `--chart-1`
  fallback).
- The styleguide chart examples use `mid` where they had the second series.

Tests: `test/d_chart_test.dart` pins the five steps' ARGB in a light and a dark
palette and the 34% share; `test/dashboard_page_test.dart` pins the traffic
kinds' tones.
