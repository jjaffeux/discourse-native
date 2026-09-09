# Kbd audit

Source-level audit of `lib/src/ui/components/d_kbd.dart` against the official
Base UI Kbd reference, performed 2026-09-09 on branch `claude/audit-kbd`.
Widget tests back every finding; no native app, simulator or browser was run.

## Reference

Fetched live with `curl -s` and read verbatim:

| Source | SHA256 |
| --- | --- |
| https://ui.shadcn.com/docs/components/base/kbd.md | `3dd0b0dacf86f4b701ae35df3efe453ba1e9995a542e0a4a004a252f5bdd7978` |
| https://ui.shadcn.com/r/styles/base-nova/kbd.json | `4cfe2ba8e19f4d19d090eb039e3f1c041c9cfb379ce948237a9b5018203f7a6c` |
| https://ui.shadcn.com/r/styles/base-nova/tooltip.json | `2f55867faecee2d3616cfd8c6a80b538909a21e62fdfa2788b1ead56093e5395` |
| https://ui.shadcn.com/r/styles/base-nova/input-group.json | `acf9c5497a6c844dee87fbd4afefb6cd8be9ce50d050d14d58a340d955e517a1` |
| https://ui.shadcn.com/r/styles/base-nova/button.json | `9ba7e870178813f0552b818a913a2792fb500c779e36395740b4973e3025d427` |
| https://ui.shadcn.com/r/styles/base-nova/button-group.json | `da9bceac03af172022b214f89561b2bf9e0cccac63d46cfe2e1c9f2c8e6792e9` |
| https://ui.shadcn.com/docs/theming.md | `403a71fea629dd9d5eebdf3656baab6b8550972adfb4fc5ed0847d13b3dc73f0` |

Both Kbd hashes equal the ones recorded by the original task, so the frozen
scope is unchanged. Registry source:

```
Kbd:      pointer-events-none inline-flex h-5 w-fit min-w-5 items-center
          justify-center gap-1 rounded-sm bg-muted px-1 font-sans text-xs
          font-medium text-muted-foreground select-none
          in-data-[slot=tooltip-content]:bg-background/20
          in-data-[slot=tooltip-content]:text-background
          dark:in-data-[slot=tooltip-content]:bg-background/10
          [&_svg:not([class*='size-'])]:size-3
KbdGroup: <kbd data-slot="kbd-group"> inline-flex items-center gap-1
```

Rules that other registry items apply to keycaps: tooltip content
`has-data-[slot=kbd]:pr-1.5` and `**:data-[slot=kbd]:rounded-sm`; input-group
addon `[&>kbd]:rounded-[calc(var(--radius)-5px)]` and
`has-[>kbd]:mr-[-0.15rem]` / `ml-[-0.15rem]`; button `has-data-[icon=inline-end]:pr-2`
with `gap-1.5`. `button.tsx` has no kbd-specific rule.

## Comparison

| Reference | Flutter (`DKbd` / `DKbdGroup`) | Status |
| --- | --- | --- |
| `h-5`, `min-w-5` (20px) | 20px minimum in both dimensions; default keycaps measure 20×20 | match at 100% text; height grows with the native text scaler (intentional, see below) |
| `w-fit`, `px-1`, `items-center justify-center` | intrinsic width, 4px horizontal padding, centered content | match |
| `gap-1` between a keycap's own children | single child; compose an icon and text with a 4px `Row` | not applicable |
| `rounded-sm` | `DTokens.radius × 0.6` (official proportional scale) | match |
| `bg-muted`, `text-muted-foreground`, no border, no shadow | `tokens.muted`, `tokens.mutedForeground`, `BoxDecoration` without border | match |
| `font-sans text-xs font-medium`, no tracking | host `labelSmall` family, 12px, 16/12 line height, w500, letter spacing 0; Material role metrics cannot override | match |
| `select-none pointer-events-none` | `SelectionContainer.disabled` + `IgnorePointer`; no focus node | match |
| `[&_svg:not([class*='size-'])]:size-3` | `IconTheme` 12px with the keycap foreground | fixed: size previously followed a custom `style` font size |
| tooltip scope: `text-background`, `bg-background/20`, dark `/10` | `DKbdTheme` from `DTooltip`: foreground = `tokens.background`, tint = foreground alpha × 0.20 / 0.10 | fixed: alpha is now multiplied, not replaced |
| tooltip `has-data-[slot=kbd]:pr-1.5` | `DTooltip.shortcut` / `containsKeycaps` reduce trailing padding to 6px | match (tooltip-owned) |
| input-group addon `[&>kbd]:rounded-[calc(var(--radius)-5px)]` | direct `DKbd` addon children receive `DKbdTheme.borderRadius = max(0, radius − 5)`; grouped keycaps keep `radius × 0.6` | fixed: was missing |
| input-group addon `has-[>kbd]:mr-[-0.15rem]` (8 − 2.4 = 5.6px inset) | 5.6px inset for `DKbd`, `DKbdGroup` and now `DShortcutKeycaps` children | fixed: `DShortcutKeycaps` addons used the 8px inset |
| button `data-icon="inline-end"` (`gap-1.5`, `pr-2`) | `DButton(icon: DKbd(...), iconPosition: end)`: 6px gap, 9px end inset including the 1px border | match (button-owned) |
| `KbdGroup` `inline-flex items-center gap-1` | `Wrap` with 4px spacing and run spacing, centered cross axis | match; wraps when constrained (intentional, see below) |
| `<kbd>` semantics | one bounded `Semantics` label per keycap with spoken symbol defaults; a labelled group replaces descendant speech | match plus spoken names |
| RTL: no directional styling; group follows `dir` | keycap has no directional geometry; group follows ambient `Directionality` with an explicit override | match |
| Demo: two centered groups, `gap-4` | first example rows 1–2 | match |
| Group: `text-sm text-muted-foreground` sentence with `Ctrl + B` / `Ctrl + K` | `DText.rich(variant: muted)` with a `WidgetSpan` group | fixed: was a different sentence |
| Button: `variant="outline"` Accept + `⏎` at `inline-end`, `translate-x-0.5` | outline `DButton`, `DKbd('⏎')` in the end icon slot, 2px inline-end nudge | fixed: was a standard button with an `F6` keycap in the label |
| Tooltip: `ButtonGroup` of two outline buttons, `Save Changes [S]`, `Print Document [Ctrl][P]` | `DButtonGroup` with `DButton.tooltip/shortcut` and a `DTooltip.content` keycap group | fixed: was a padded text trigger |
| Input Group: `Search...`, search icon addon, `inline-end` `⌘` `K`, `max-w-xs` | `DInputGroup`, `DInputGroupAddon(child: Icon(Icons.search))`, inline-end `DKbd` pair, 320px bound; the modifier keycap follows the platform binding | fixed: was a native `TextField` suffix |
| RTL: demo groups under `dir="rtl"` | the two demo groups under `DDirection(rtl)` plus the LTR notation island | fixed: only app-specific groups were shown |
| API: `className` | typed `style`, `child`, `semanticLabel`, `highlighted`; group `spacing`, `runSpacing`, `textDirection`, `semanticLabel` | equivalent; no inert property |

Shortcut helpers (`DShortcut`, `DShortcutKeycaps`, app extension): keycaps render
through `DKbd` and `DKbdGroup` with the reference visuals; Apple notation is
⌃ ⌥ ⇧ ⌘ in the HIG order with spoken Control / Option / Shift / Command, and
Linux uses Ctrl / Alt / Shift / Meta.

## Intentional differences

- Height is a 20px minimum, not a fixed 20px, and groups wrap: a fixed height
  or an unwrappable row clips or overflows at the required 200% text scale and
  240px preview width (`kbd_examples_test.dart` pins both).
- `highlighted` (primary colors, w600, underline) is an additive feedback state
  used by tooltips and shortcut hints; default keycaps keep the reference look.
- The tooltip sample scrolls its `DButtonGroup` horizontally at narrow widths
  because a joined group cannot wrap; the reference `flex-wrap` container only
  wraps between groups.

## Issues

"Fixed" means commit `483fa53b` on `claude/audit-kbd`.

| # | Finding | Status |
| --- | --- | --- |
| 1 | Named keys were upper-cased (`Page Down` → `PAGE DOWN`, `Home` → `HOME`) on keycaps and in spoken labels; only single characters should read as printed keycaps. | fixed |
| 2 | Icon size followed a custom `style` font size instead of the reference 12px. | fixed |
| 3 | Input-group addons did not apply `[&>kbd]:rounded-[calc(var(--radius)-5px)]`; `DKbdTheme` gained an optional `borderRadius` that `DInputGroupAddon` supplies to direct `DKbd` children. | fixed |
| 4 | `DShortcutKeycaps` inside an addon used the 8px text inset instead of the 5.6px keycap inset. | fixed |
| 5 | Tooltip keycap tint replaced alpha instead of multiplying it (`visual-fidelity.md`). | fixed (`d_tooltip.dart`, one expression) |
| 6 | `DShortcutKeycaps` called `setState` on every hardware key event while listening, including repeats and unrelated typing, rebuilding keycaps inside every open tooltip or hint. The handler now compares the packed feedback state with what was last built. | fixed |
| 7 | Styleguide did not reproduce the documented Group, Button, Tooltip, Input Group and RTL compositions; notes still called Button, Tooltip and Input Group unfinished. | fixed |
| 8 | Linux modifier order is Ctrl / Alt / Shift / Meta; Flutter's own `MenuItemButton` labeler uses Alt / Ctrl / Meta / Shift on non-Apple platforms. Conventions differ between toolkits and the reference shows literal children only. | open, needs a product decision |
| 9 | Default spoken key names and the "then" separator are English; callers localize through `semanticLabel`. | open, pre-existing limitation |

No lifecycle leak, stale cached theme value or async race was found: listeners
are removed on disable and dispose, colors are read in `build`, and the
feedback state stays owned by the widget.

## Verification

```
dart format lib/src/ui/components/d_kbd.dart lib/src/ui/components/d_input_group.dart \
  lib/src/ui/components/d_tooltip.dart lib/src/styleguide/examples/kbd_examples.dart \
  test/ui/d_kbd_test.dart test/styleguide/kbd_examples_test.dart test/d_input_group_test.dart
flutter analyze --no-pub                       # root: No issues found
(cd profiles/full && flutter analyze --no-pub) # No issues found
flutter test --no-pub --test-randomize-ordering-seed=random \
  test/ui/d_kbd_test.dart test/styleguide/kbd_examples_test.dart test/d_input_group_test.dart
  # 39 passed, seed 2433166817
flutter test --no-pub --test-randomize-ordering-seed=random \
  test/d_tooltip_test.dart test/ui_tooltip_test.dart test/styleguide/styleguide_page_test.dart \
  test/styleguide/input_group_examples_test.dart test/styleguide/tooltip_examples_test.dart \
  test/styleguide/empty_examples_test.dart test/d_button_test.dart test/d_button_group_test.dart \
  test/styleguide/button_group_examples_test.dart test/keyboard_shortcuts_help_test.dart \
  test/forum_search_clear_accessibility_test.dart test/forum_tabs_integration_test.dart
  # 147 passed, seed 2643263224
git diff --check                               # clean
```

The consumer run covers every `DKbdTheme` owner (`d_tooltip.dart`,
`d_input_group.dart`) and every app caller of `DKbd`, `DShortcut` and
`DShortcutKeycaps` found by grep across `lib/` and `profiles/`.
