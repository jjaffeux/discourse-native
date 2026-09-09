# Badge reference audit (2026-09-09)

Source-level audit of `lib/src/ui/components/d_badge.dart`, its styleguide
examples, tests and app callers against the live shadcn base-nova Badge.
No native app, simulator or browser was run; every claim below is backed by
the fetched reference text, the compiled website stylesheet, or a widget test.

## References

| Source | SHA256 | Drift |
| --- | --- | --- |
| [Docs page](https://ui.shadcn.com/docs/components/base/badge.md) | `e174d14915336a823d0926ac774ba56767fd315950ac843dbe58fc36aba507bf` | none; equals `reference/badge.md` |
| [base-nova registry](https://ui.shadcn.com/r/styles/base-nova/badge.json) | `ccc20021cdcbf0fb23c0d4d28f1da4adde8e51ba59f4b11dd2722ed97a5ee3a4` | none; equals `reference/badge.json` |
| [Compiled website stylesheet](https://ui.shadcn.com/_next/static/immutable/chunks/17udeju1vgrir.css) | `19dd8fe80f1fb07e156ed3ceaaaacb7a600a3444e97c3baf6483c4363a15668d` | none; equals the chunk recorded in `evidence/badge/reference-ring-css.json` |

Tailwind mapping: `--spacing` .25rem = 4px, `--text-xs` .75rem with
`calc(1/.75)` leading = 12/16px, `--font-weight-medium` 500,
`--default-transition-duration` .15s,
`--default-transition-timing-function` `cubic-bezier(.4, 0, .2, 1)`,
`.rounded-4xl { border-radius: calc(var(--radius) * 2.6) }`.

## Reference to Flutter comparison

| Reference | Flutter (`DBadge`) | Result |
| --- | --- | --- |
| `inline-flex w-fit shrink-0 items-center justify-center` | Minimum-size `Row`, centered cross axis, flexible label | match |
| `h-5` border-box 20px | `minHeight: 20` = 1px border + 1px inset + 16px line + 1px inset + 1px border | match |
| `px-2 py-0.5` (8px / 2px) | 8px logical sides; 1px inset + 1px border vertically | match |
| `has-data-[icon=inline-start]:pl-1.5`, `...inline-end:pr-1.5` (6px) | 6px on the side that carries `leading` / `trailing`, directional | intentional (see issue 9) |
| `gap-1` 4px | `SizedBox(width: DSpacing.xs)` between slots | match |
| `[&>svg]:size-3! pointer-events-none` | 12px `SizedBox.square` + `FittedBox`, `IgnorePointer`, `ExcludeSemantics`, `ExcludeFocus` | match |
| `rounded-4xl` = 2.6 × `--radius` | `BorderRadius.circular(tokens.radius * 2.6)` | match |
| `border border-transparent`; outline `border-border` | Always 1px; `tokens.border` for outline, else transparent | match |
| `overflow-hidden` | `Clip.antiAlias`; ring painted as an exterior foreground decoration | match |
| `text-xs font-medium`, no tracking | `DiscourseTypography.xs` 12, height 16/12, w500, `letterSpacing: 0`; host family | match |
| `whitespace-nowrap` | Wraps only when the parent constrains width | intentional (issue 8) |
| default: `bg-primary text-primary-foreground [a]:hover:bg-primary/80` | primary / primaryForeground; interactive hover alpha × .8 | match (issue 10 for `.action`) |
| secondary: `bg-secondary text-secondary-foreground [a]:hover:bg-secondary/80` | muted / foreground; hover × .8 | open (issue 5) |
| destructive: `bg-destructive/10 dark:bg-destructive/20 text-destructive [a]:hover:bg-destructive/20` | destructive × .1 light / × .2 dark / × .2 hover; destructive text | match |
| outline: `border-border text-foreground [a]:hover:bg-muted [a]:hover:text-muted-foreground` | transparent / foreground; interactive hover muted / mutedForeground | match |
| ghost: `hover:bg-muted hover:text-muted-foreground dark:hover:bg-muted/50` (any render) | muted (× .5 dark) / mutedForeground on hover, static included | match; now pinned by test |
| link: `text-primary underline-offset-4 hover:underline` (any render) | primary text; underline on hover, static included | match except offset (issue 7) |
| `focus-visible:border-ring focus-visible:ring-[3px] focus-visible:ring-ring/50` | focus: `focusRing` border, exterior 3px ring at × .5 | match; ring token is `primary` (issue 6) |
| destructive `focus-visible:ring-destructive/20 dark:...ring-destructive/40` | destructive ring × .2 / × .4; `cn` drops the base `ring-ring/50` for this variant | match |
| `aria-invalid:border-destructive aria-invalid:ring-destructive/20 dark:...ring-destructive/40` | destructive border always; destructive ring only while focus-visible (3px width is focus-scoped) | match |
| Invalid + focused border precedence | `aria-invalid:border-destructive` (offset 278946) follows `focus-visible:border-ring` (237277) at equal specificity, so destructive wins | match |
| `transition-all` 150ms `cubic-bezier(.4,0,.2,1)` | 150ms `Cubic(.4, 0, .2, 1)`; zero under reduced motion | fixed (issue 1) |
| Span text selectable (no `select-none`) | Participates in an enclosing `SelectionArea` | fixed (issue 2) |
| Static span mounts no hover handler unless a `hover:` rule applies | Only ghost/link/interactive badges track the pointer | fixed (issue 3) |
| Disabled | Not in the reference; `.action`/`.link` with null callback: 50% opacity, `enabled: false`, no tab stop | intentional (issue 11) |
| `span` (no role) / `<a href>` render / button render | none / `link` + `linkUrl` / `button`; Enter on links, Enter + Space on actions | match |
| Touch target | 48px invisible target around the 20px visual on iOS/Android/Fuchsia only | intentional (issue 12) |
| Custom colors via `className` | `backgroundColor` / `foregroundColor` / `borderColor` read each build | match (issue 13 for hover) |
| Examples: demo, Variants, With Icon, With Spinner, Link, Custom Colors, RTL | Six styleguide sections cover every documented section; the registry's Long Text label is included | match; RTL Hebrew added (issue 4) |
| Lucide `BadgeCheck`, `Bookmark`, `ArrowUpRight` at 12px | Frozen live-bundled paths, 24 view box, 2px round strokes, `currentColor` | match |

## Implementation review

Owned focus node disposed, borrowed never; all colors and the transition
duration are read in `build`; `onPressed` is read at activation time; a
disabled rebuild clears `_pressed`; `Semantics` is a container only for
interactive badges so a static count merges into its parent control. Every
public property is wired (`url` is accessibility metadata by contract).
App callers (`topic_list_indicators.dart`, `user_menu.dart`,
`user_card.dart`, `groups_page.dart`, `group/group_members_view.dart`,
`plugins/chat/chat_drawer.dart`) construct static badges only; none sits
inside a `SelectionArea`, so the selection change alters nothing they render.

## Issues

1. Transition curve was `Curves.easeInOut` (0.42, 0, 0.58, 1), not the
   reference `cubic-bezier(.4, 0, .2, 1)`. Fixed in `fb389790`; the ring
   pixel test samples at 50ms because the reference curve is ~77% complete
   at 75ms.
2. `SelectionContainer.disabled` excluded badge text from selection; the
   reference span has no `select-none` (Button, Kbd and Label do). Fixed in
   `fb389790` with a `SelectionArea` test.
3. Every static badge mounted a `MouseRegion` and rebuilt on pointer
   enter/exit although only ghost and link paint on a static span. Fixed in
   `fb389790`: other static variants skip hover tracking; a variant change
   away from ghost/link clears the last observed hover because a removed
   `MouseRegion` reports no exit. Tests pin static ghost/link hover, the
   unchanged build count of a hovered primary badge, and the stale-hover reset.
4. RTL example offered only Arabic and English; the documented selector has
   `ar`, `en` and `he`. Fixed in `fb389790`: the example cycles all three.
5. `secondary` maps to `muted` / `foreground`. `DTokens` has no
   `secondary` / `secondaryForeground` role and `DButton` uses the same
   mapping; the default themes give `secondary-foreground` a different
   lightness than `foreground` in light mode. Open: adding the role is a
   shared foundation decision affecting Button as well.
6. Focus ring uses `DTokens.focusRing` (host primary) where the reference
   `--ring` is neutral gray. Intentional, shared token mapping recorded in
   `badge-native.md`.
7. `underline-offset-4` has no `TextDecoration` equivalent. Open: would need
   a custom underline painter; native font placement is retained.
8. `h-5 whitespace-nowrap` never wraps; the reference overflows its parent.
   Intentional: Flutter overflow is an error state, and 200% text or 360px
   layouts must keep the label readable, so the label wraps only when the
   parent constrains it. At unconstrained widths the geometry is identical.
9. `pl-1.5` / `pr-1.5` compile to physical `padding-left` / `padding-right`
   while `px-2` is logical `padding-inline`, so in the reference RTL example
   the reduced inset lands on the text side. Intentional: the inset follows
   `leading` / `trailing` logically, which is what `inline-start` /
   `inline-end` name.
10. `[a]:hover:*` applies only to anchor renders; `DBadge.action` (button
    semantics) shares the same interactive hover. Intentional: the reference
    documents no button render, and the native action form is the
    activation counterpart of the link render.
11. Disabled treatment does not exist in the reference. Intentional native
    extension mirroring Button's `disabled:opacity-50`, paired with
    `enabled: false` semantics and no tab stop.
12. 48px touch target on touch platforms. Intentional; invisible and only for
    interactive badges.
13. A custom `className` background on an anchor render is overridden by
    `[a]:hover:bg-primary/80`; `backgroundColor` stays on hover here.
    Intentional: explicit props are not class merges.
14. Geist vs host font metrics and sRGB-clipped OKLCH custom colors remain
    documented platform differences.

## Verification

- `flutter analyze --no-pub` at the root: No issues found.
- `dart format` on `d_badge.dart`, `badge_examples.dart`, `d_badge_test.dart`,
  `badge_examples_test.dart`, `d_badge_ring_test.dart`: 0 changed.
- `flutter test --no-pub --test-randomize-ordering-seed=random
  test/d_badge_test.dart test/d_badge_ring_test.dart
  test/badge_migrations_test.dart test/styleguide/badge_examples_test.dart
  test/styleguide/styleguide_page_test.dart`: 53 passed, seed 313057812.
- Callers and adopters, `flutter test --no-pub
  --test-randomize-ordering-seed=random test/groups_page_test.dart
  test/group_page_test.dart test/user_card_test.dart
  test/user_card_target_accessibility_test.dart
  test/user_card_account_lifecycle_test.dart
  test/user_menu_message_accessibility_test.dart
  test/plugin_user_menu_widget_test.dart test/chat_drawer_test.dart
  test/chat_shell_integration_test.dart test/topic_list_view_lifecycle_test.dart
  test/styleguide/spinner_examples_test.dart
  test/styleguide/data_table_examples_test.dart
  test/styleguide/item_examples_test.dart
  test/styleguide/card_examples_test.dart`: 250 passed, seed 575560223.
- No shared foundation file changed; `profiles/full` exports are unchanged.
