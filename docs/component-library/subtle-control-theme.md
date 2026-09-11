# Subtle control theme colors

2026-09-11: map the shared input color (`ColorScheme.outlineVariant`) to
the site's `primaryLow`, instead of `primaryLowMid`. Built-in palettes use
their existing shell divider color. This softens outline button and selector
borders and their translucent dark fills through existing UI kit behavior.
No component API or interaction changes are needed.

Reference: the supplied shadcn dropdown screenshot and
https://ui.shadcn.com/docs/theming (`input` owns control borders and surfaces).

Verification:

- Dart formatting and targeted static analysis passed.
- 85 tests passed across app_theme, control_consistency,
  control_consistency_golden, d_button, d_select and topic_taxonomy_selectors.
- Reviewed and updated six light/dark control goldens (rest, hover, open).
  These use Flutter's widget-test renderer, repository JetBrains Mono and
  Material Icons at 720 × 480; forest/plum baselines remained unchanged.
- Ran `tool/control_consistency_review_main.dart` on macOS with Skia/Metal.
  Inspected dark/light/plum controls, production taxonomy triggers, joined
  bookmark/notification actions, and 640/320 preview widths. Opened a category
  menu, selected Support, and opened the notification menu. Native selector
  clicks showed focus but did not visibly open its popup in this review;
  selector interaction coverage passed in widget tests. No mobile device run.
