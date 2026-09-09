# Direction audit

Audited 2026-09-09 on branch `claude/audit-direction` from main `9c4abfed`.
Source-level audit backed by widget tests; no native or browser run.

## Reference

| Source | SHA256 |
| --- | --- |
| https://ui.shadcn.com/docs/components/base/direction.md (5312 bytes) | `696841f1a8259dfdb07c8b9ecc82181a4b0daf36516ba1a63164542970cfb709` |
| https://ui.shadcn.com/r/styles/base-nova/direction.json (582 bytes) | `bf226602a949b5da7b3f8b3cbd0ed962d1e5d8a76c634055cdb05816c6bd1f32` |
| https://base-ui.com/react/utils/direction-provider.md (linked API) | `7e3190c679a28f50b82684f9766a16722b6147f6934766ef85acd11303e73577` |
| shadcn-ui/ui `apps/v4/components/language-selector.tsx` (docs-site demo helper, not a registry item) | `e2259ad2b58f87b5b96f71feae23ffa3d2e76200b13dd9d10726d101992ce6d5` |
| https://ui.shadcn.com/docs/theming.md | `403a71fea629dd9d5eebdf3656baab6b8550972adfb4fc5ed0847d13b3dc73f0` |

The registry file is two lines: `export { DirectionProvider, useDirection }
from "@base-ui/react/direction-provider"`. It has no cva, classes, geometry,
colors, icons or motion. The Base UI API is `direction: 'ltr' | 'rtl'`
(default `'ltr'`), `children`, and `useDirection(): 'ltr' | 'rtl'`, which
answers `'ltr'` without a provider. The docs page has one demo, `CardRtl`: a
`max-w-sm` login Card with `dir` and strings from `useTranslation` (default
`ar`), switched by the site's `LanguageSelector`, a `size="sm"` `w-36` Select
with `dir="ltr"` on its trigger and content and the options English,
Arabic (العربية), Hebrew (עברית).

## Comparison

| Reference | Flutter | Status |
| --- | --- | --- |
| `DirectionProvider` with `children` | `DDirection(child:)` wrapping `Directionality` | match |
| `direction` typed `'ltr' \| 'rtl'` | `TextDirection? textDirection` | match |
| Omitted `direction` defaults to `'ltr'` | null inherits the nearest provider (host locale) | intentional, below |
| `useDirection()` reads the nearest provider; `'ltr'` without one | `DDirection.of` reads the nearest provider and throws without one; `maybeOf` answers null | intentional, below |
| Provider changes Base UI behavior only; `dir`/CSS are set separately | one provider drives layout, text, semantics and focus traversal | match (documented superset) |
| Context change re-renders consumers | inherited dependents rebuild; child state, edits, selection and focus retained across explicit/inherit switches | match, tested |
| Nested providers, nearest wins | nested `DDirection`/`Directionality`, nearest wins | match, tested |
| `useDirection` for portaled content | `OverlayPortal` consumers (`DSelect`, `DDropdownMenu`) keep the originating scope while open | match, tested |
| Preview demo `CardRtl`: language selector, login card in the language's direction, selector fixed LTR, Arabic default | `Card RTL` example: `DSelect` small/144px in an explicit LTR scope, `DCard`/`DField`/`DInput`/`DButton` login card, Arabic default, drafts and validation retained | fixed |
| Installation `@base-ui/react` | `package:discourse_native/discourse_ui.dart` | match |
| Usage: provider above the whole app | `MaterialApp.builder` → `DDirection` above the Navigator; now in the notes and example code | fixed |
| `useDirection` section | `DDirection.of(context)` readouts | match |
| Variants, sizes, states, geometry, typography, colors, icons, motion, keyboard, roles, positioning | none in the reference | n/a |
| RTL | the component is the RTL owner | match |

## Implementation review

`DDirection` is stateless with no controllers or focus nodes. `of(context)`
is only evaluated when `textDirection` is null, so an explicit scope does not
subscribe to ancestor changes. Nothing is cached across builds and no
semantics are added; `Text` reads the same provider. Exported through
`discourse_ui.dart`; app callers only use `DDirection.of`, whose behavior is
unchanged.

## Issues

1. The documented `CardRtl` preview was not reproduced; the original decision
   deferred it until Card, Input, Label, Field, Select and the link Button
   existed. Fixed in `d52a5eec`.
2. The app-specific examples used Material `ChoiceChip` and `TextField`.
   Fixed in `d52a5eec` with `DToggleGroup` and `DInput`.
3. The app-wide Usage snippet had no Flutter equivalent in the styleguide.
   Fixed in `d52a5eec` (notes and example code).
4. The widget inspector showed no direction for a `DDirection` node, unlike
   `Directionality`. Fixed in `d52a5eec` with `debugFillProperties`.
5. A null `textDirection` inherits rather than resetting to LTR. Intentional:
   `WidgetsApp` already owns the locale direction, so an implicit LTR reset
   would flip an Arabic-locale subtree merely by wrapping it. The reference
   needs its default because Base UI cannot read the DOM `dir`. Pass
   `TextDirection.ltr` for the reference behavior. Documented on the widget.
6. `DDirection.of` throws without an ancestor instead of answering LTR.
   Intentional: it is the same provider as `Directionality.of`, and every
   directional layout in that subtree fails the same way; a silent LTR would
   misreport what the subtree lays out with. `maybeOf` is the nullable form.
   Documented on the widget.
7. The docs-site selector disables its popup animation
   (`data-open:animate-none`). Open: docs-site chrome, not the Direction
   contract; `DSelect` keeps its popover motion and honours reduced motion.
8. The login composition duplicates Card's private `_Login` and
   `_RecoveryLink` example code. Open: kept self-contained to avoid editing
   Card's examples during concurrent audits; a shared example source can
   replace both copies once the audits merge.
9. The readouts keep Material `Icons.arrow_forward`. Open, minor: it is a
   `matchTextDirection` glyph demonstrating mirroring; `DIcons` has no
   arrow-right and `DIcon` does not mirror.

## Verification

- `dart format --output=none --set-exit-if-changed` on the five touched
  files: 0 changed.
- `flutter analyze --no-pub` (root): no issues.
- `flutter test --no-pub --test-randomize-ordering-seed=random
  test/ui/d_direction_test.dart test/styleguide/direction_examples_test.dart`:
  27 passed, seed `3596502098`.
- `flutter test --no-pub --test-randomize-ordering-seed=random
  test/styleguide/styleguide_page_test.dart
  test/styleguide/styleguide_access_test.dart test/resizable_pane_test.dart
  test/keyboard_shortcuts_help_test.dart`: 31 passed, seed `1309539282`.
- No shared foundation file, app caller, lockfile or catalogue file changed.
