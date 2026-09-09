# Separator audit

Audit date: 2026-09-09. Branch `claude/audit-separator` from local main
`9c4abfed`. Source-level audit backed by widget tests; no device, simulator or
browser session was used.

## References

Fetched with `curl -s` and read verbatim:

| Source | SHA256 |
| --- | --- |
| [Docs page markdown](https://ui.shadcn.com/docs/components/base/separator.md) | `b0c3b29e2b3852570144159da0ee5681074c1ddb1727d2f720a7b211f1259120` |
| [Registry `base-nova/separator.json`](https://ui.shadcn.com/r/styles/base-nova/separator.json) | `3ad65962485f464592201cb90017b3d52a5c9fe272ce41ee049485b4c42e0d76` |
| [Base UI Separator page](https://base-ui.com/react/components/separator) (HTML) | `8550405e979364a22c0a593803a948b2929d7fedb2e1ecb2998cd6c3921cc07f` |

The docs page hash equals the frozen 2026-09-08 hash recorded in the
`separator` progress row. The live registry JSON parses equal to
`docs/component-library/reference/separator.json` (same file hash; component
TSX content hash `9a80ff8c110e0c55489509f4f82ebcc929c0174b59544047147b7134f86a54e7`).
No upstream drift.

Registry classes: `shrink-0 bg-border data-horizontal:h-px
data-horizontal:w-full data-vertical:w-px data-vertical:self-stretch`, default
`orientation="horizontal"`. Base UI renders a `div` with `role="separator"`,
`aria-orientation` and `data-orientation`; it has no `decorative` prop.

## Reference to Flutter

| Reference | Flutter (`DSeparator`) | Result |
| --- | --- | --- |
| `h-px` / `w-px`: 1 CSS px line; box is the line | `thickness: 1` default; `space` defaults to the thickness, so the box is 1 logical px | match |
| `bg-border` | `color ?? DTokens.of(context).border`, read on every build | match |
| Square ends, no radius | `radius ?? BorderRadius.zero` | match |
| `w-full`: fills the parent width | `Divider` expands to bounded width; explicit `length` for unbounded parents | match (bounded); collapses to 0 with no `length` in an unbounded axis, documented |
| `self-stretch`: vertical line fills the flex row's height | `VerticalDivider` expands to a finite row height (fixed `h-5` row: 20px); an unbounded row needs `IntrinsicHeight` | match with `IntrinsicHeight`; a child cannot size to siblings in Flutter's single-pass layout, so a bare unbounded row collapses to 0 without error (tested) |
| `shrink-0` | non-flex Row/Column child never shrinks | match |
| `orientation` prop, default horizontal | `orientation: Axis`, default `Axis.horizontal` | match |
| `role="separator"` + `aria-orientation` on every instance | `SemanticsRole` in Flutter 3.47.2 has no separator value and no orientation attribute (`dart:ui` enum listed during the audit). Decorative default excludes the line; `decorative: false` + `semanticLabel` exposes a static labeled boundary with no actions | intentional; concrete conflict in the framework, no invented role |
| `className` / `style` / `render` | `length`, `space`, `indent`, `endIndent`, `color`, `radius`, `thickness` and ordinary composition | native extension |
| RTL: no directional treatment | horizontal insets use `EdgeInsetsDirectional`, vertical insets are top/bottom; the plain line is direction-agnostic | match |
| Docs example Usage: `max-w-sm flex-col gap-4 text-sm`, title `leading-none font-medium`, `gap-1.5`, muted subtitle | 384px column, 16px gaps, 14px/14 w500 title, 6px gap, 14/20 muted subtitle, 14/20 description | match (fixed on this branch) |
| Docs example Vertical: `flex h-5 items-center gap-4` with text items | `IntrinsicHeight` > `ConstrainedBox(minHeight: 20)` > `Row(spacing: 16)`; 20px row at 100% text; lines fill it | match; 20px is a minimum so 200% text grows the row instead of overflowing |
| Docs example Menu: `flex items-center gap-2 md:gap-4`, two-line items, Help `hidden md:flex` | `IntrinsicHeight` row, gap 8 below a 768px `MediaQuery` width and 16 from it, Help and its separator omitted below 768 | match (fixed on this branch; the old example stacked below 520px) |
| Docs example List: `w-full max-w-sm flex-col gap-2`, `dl` rows `justify-between` | full-width column ≤ 384px, 8px gaps, three 20px space-between rows | match (fixed on this branch; the old example used Material `ListTile`) |
| Docs example RTL: Usage layout, `dir` from an en/ar/he selector, default `ar` | `DSelect` language choice, `DDirection` on the demo, the reference strings | match (fixed on this branch) |
| Flex items `flex-shrink: 1` (text wraps in narrow rows) | `Flexible` items in the Vertical, Menu and List rows | match; a single word longer than its share clips instead of overflowing the row |

## Issues

1. `thickness: 0` (documented hairline) with a non-null `radius` failed
   Flutter's `Border.paint` assertion "A hairline border ... can only be drawn
   when BorderRadius is zero or null" at paint time in debug and drew nothing
   in release. Fixed in `4985531f`: constructor assert with a message; doc
   comment states the constraint; tests pin a painted hairline stroke and the
   rejected combination.
2. The styleguide did not reproduce the documented Usage, Vertical, Menu, List
   and RTL compositions (DButton navigation, Material `ListTile` list, stacked
   menu, substitute copy). Fixed in `3d6e6ac1`: each documented section is
   reproduced at reference geometry, the native-only properties moved to one
   final example, and the examples test asserts the geometry per section.
3. The old Menu example kept Help visible by stacking below 520px, documented
   as a native adaptation without a conflict. Aligned with the reference in
   `3d6e6ac1`: Help and its separator are hidden below the 768px `md` viewport
   width, which the styleguide's 768/1024 presets reach.
4. Base UI exposes every separator as `role="separator"` with
   `aria-orientation`. Intentional deviation retained: Flutter 3.47.2 has no
   separator `SemanticsRole` and no orientation attribute, so the widget keeps
   the decorative default and the labeled meaningful mode rather than
   inventing a role. Revisit when the framework adds one.
5. A vertical line in a Row of unbounded height collapses to zero height
   silently. Intentional and now tested: Flutter layout cannot size a child to
   its siblings; the documented `IntrinsicHeight` composition matches the
   reference `self-stretch`, and the Menu example demonstrates it.
6. Open, not fixed: the examples are verified by widget tests with the test
   font only. A native styleguide comparison of the new compositions against
   the reference (fonts, 768/1024 presets, VoiceOver) remains for the reviewer;
   this audit ran no app, simulator or browser.

Consumers (`DButtonGroupSeparator`, `DFieldSeparator`, `DItemSeparator`,
`DSidebarSeparator`, Scroll Area examples, 70+ app call sites under
`lib/src/shell` and `lib/src/plugins`) pass `thickness >= 1` or the default and
are unaffected by the new assert; their tests were re-run below.

## Verification

- `flutter pub get --enforce-lockfile`: passed, no lockfile change.
- `dart format --output=none --set-exit-if-changed` on the four touched Dart
  files: 0 changed.
- `flutter analyze --no-pub`: no issues. `profiles/full` unchanged (no export
  or shared-code change).
- `flutter test --no-pub --test-randomize-ordering-seed=random test/ui/d_separator_test.dart`:
  17 passed, seed 3942804696.
- `flutter test --no-pub --test-randomize-ordering-seed=random test/styleguide/separator_examples_test.dart test/styleguide/styleguide_page_test.dart`:
  29 passed, seed 3440400370.
- `flutter test --no-pub --test-randomize-ordering-seed=random test/d_button_group_test.dart test/d_item_test.dart test/ui/d_field_test.dart test/d_sidebar_test.dart test/d_scroll_area_test.dart test/styleguide/button_group_examples_test.dart test/styleguide/item_examples_test.dart test/styleguide/field_examples_test.dart test/styleguide/sidebar_examples_test.dart test/styleguide/scroll_area_examples_test.dart test/anchored_picker_test.dart test/forum_tabs_bar_test.dart test/group_page_test.dart test/topic_day_separator_test.dart`:
  159 passed.
