# Button audit — 2026-09-09

Catalogue id `button`. Branch `claude/audit-button`, worktree
`.claude/worktrees/agent-a80ac546eeafe84b6`, base `9c4abfed`. Source-level
audit backed by widget tests; no native run, simulator or browser session.

## Reference

Fetched with `curl -s` on 2026-09-09:

| Source | SHA256 |
| --- | --- |
| [Docs Markdown](https://ui.shadcn.com/docs/components/base/button.md) | `966cf16702128d2b385b62616ee24bb3b1b3b2ed7eebfc13ce411c90421f8910` (unchanged from the frozen copy) |
| [base-nova registry](https://ui.shadcn.com/r/styles/base-nova/button.json) | `9ba7e870178813f0552b818a913a2792fb500c779e36395740b4973e3025d427` (unchanged) |
| [Theming](https://ui.shadcn.com/docs/theming.md) | `403a71fea629dd9d5eebdf3656baab6b8550972adfb4fc5ed0847d13b3dc73f0` |
| [Spinner registry](https://ui.shadcn.com/r/styles/base-nova/spinner.json) | `d949d0b91ff34620eecf2bb359536fd3e6942b518dc0a396b77fd02a90661b61` |
| Live stylesheet `/_next/static/immutable/chunks/17udeju1vgrir.css` | `19dd8fe80f1fb07e156ed3ceaaaacb7a600a3444e97c3baf6483c4363a15668d` |

The compiled stylesheet settles cascade questions the class string leaves
open. Rule offsets: `.focus-visible\:border-ring` 237277,
`.aria-expanded\:bg-muted` 278034, `.aria-expanded\:bg-secondary` 278109,
`.aria-invalid\:border-destructive` 278946, `.dark\:border-input` 425177,
`.dark\:bg-input\/30` 427370, `.dark\:hover\:bg-input\/50` 436420 (three-class
specificity), `.dark\:hover\:bg-muted\/50` 436696. Every `hover:` utility sits
inside `@media (hover: hover)`. Consequences: a focused dark outline keeps its
`input` border; an expanded dark outline keeps its resting `input/30` fill; an
expanded secondary trigger keeps `bg-secondary` even while hovered; touch
devices get no hover fill, only the `active:` translate.

Lucide artwork for the Button Group section was added to
`reference/button-icons.json` with hashes (`trash-2` from the pinned
`lucide-static@1.43.0` package; the repository `main` branch no longer serves
that file).

## Comparison

| Reference | Flutter | Result |
| --- | --- | --- |
| Sizes: h-8/6/7/9, px-2.5 (xs px-2), inline icon pl/pr-2 (xs/sm 1.5), gap-1.5 (xs/sm 1), text-sm 14/20, xs 12/16, sm 0.8rem = 12.8/22.4, weight 500 | 32/24/28/36 minimum height, 11/9 (xs 9/7) padding including the 1px border, 6/4 gap, 14/20, 12/16, 12.8/22.4, w500, tracking 0 | match |
| Icon sizes: size-4, xs size-3, sm size-3.5, icon-sm size-4 | 16, 12, 14, icon-only small 16 | match |
| Spinner keeps its own `size-4` in every button size | Was 12/14px in xs/sm; now 16px everywhere | fixed |
| Radius rounded-lg; xs/icon-xs min(md, 10px); sm/icon-sm min(md, 12px) | `tokens.radius`; `.8×` capped at 10/12; caller `borderRadius` and joined groups override | match |
| `border border-transparent bg-clip-padding` | Fill painted the whole box through the transparent border; now the fill stops at the 1px border | fixed |
| default: primary, hover primary/80 | primary, hover ×.8 alpha | match |
| outline: border-border bg-background hover muted; dark border-input bg-input/30 hover input/50 | `border`/`background`/`muted`; dark `outlineVariant` ×.3/.5 with the token's own alpha | match |
| secondary: bg-secondary, hover color-mix(oklch, secondary, foreground 5%) | `muted` (the app has no separate secondary token) and sRGB 5% lerp | intentional (shared token mapping; oklch mixing unavailable) |
| ghost: hover muted, dark muted/50 | transparent, hover `muted` ×(dark ? .5 : 1) | match |
| destructive: bg/10 text-destructive hover/20; dark /20 → /30 | same factors on `destructive` | match |
| link: text-primary, underline on hover, underline-offset-4 | primary text, hover underline; no underline offset control in Flutter | match (offset limitation) |
| aria-expanded: outline/ghost bg-muted; secondary bg-secondary; dark outline unchanged; secondary outranks hover | Was always the hover surface; now per-variant expanded surface with the cascade precedence above | fixed |
| focus-visible: border-ring + 3px ring/50; destructive border/40 + ring/20 (dark /40); dark outline keeps border-input | Ring painted as an exterior 3px stroke; dark outline border now stays `input`. The ring was clipped by the Material on every standalone button (clipBehavior defaulted to antiAlias when a backgroundBuilder is set); now `Clip.none` everywhere and pixel-tested | fixed |
| aria-invalid: border-destructive (dark /50) + ring destructive/20 (dark /40) | same, alpha multiplied | match; semantics added |
| active: translate-y-px unless aria-haspopup | Was only the padded content moving; now fill, border, ring and content translate together; `hasPopup` suppresses | fixed |
| hover behind `(hover: hover)` | Reference variants change fill only on pointer hover; a touch press translates without a fill change. Compatibility variants keep their pressed fill | fixed (reference variants) / intentional (compatibility) |
| disabled: pointer-events-none, opacity-50 | `Opacity(disabledOpacity)` default .5, no activation, basic cursor | match |
| transition-all 150ms ease | Fill and border colors snapped (Material never animates colour); now one `AnimatedContainer` with `DButtonDecoration`, 150ms `Curves.ease`, zero under reduced motion | fixed |
| cursor: default (pointer optional per the Cursor section) | click cursor | intentional (app convention allowed by the docs) |
| `whitespace-nowrap`, `select-none` | one line with ellipsis; rich labels may opt into wrapping | match (ellipsis is an addition) |
| Semantics: button role, aria-label for icon buttons, aria-expanded, aria-invalid | button/link roles; tooltip becomes the icon name; `expanded` now exposed with `hasPopup`; `invalid` now sets `SemanticsValidationResult.invalid` | fixed |
| Keyboard: Enter/Space, focus restoration after navigation | FilledButton actions; Navigator/DPopover restore focus (tested) | match |
| Touch target | 48px invisible targets on iOS/Android, compact desktop surfaces | intentional (native touch accessibility) |
| Examples: hero, Size, six variants, Icon, With Icon, Rounded, Spinner, Button Group, As Link, RTL | All present; Button Group was a manual radius join and now reproduces the documented nested `DButtonGroup` + `DDropdownMenu` composition (Go Back from 640px, groups, Label As… radio submenu, destructive Trash) with the exact Lucide artwork | fixed |

## Implementation review

- `DiscourseButtonTheme.focusRingColor` was stored, lerped and copied but
  never read: removed (no caller passed it).
- `clipBehavior` was `null` for standalone buttons, which `ButtonStyleButton`
  turns into `Clip.antiAlias` whenever a `backgroundBuilder` exists, so the
  exterior focus/invalid ring was clipped away outside Button Groups.
- The public `DButtonDecoration` now owns fill, border and ring painting.
  Tests read it through `test/support/button_surface.dart` instead of
  `ButtonStyle.backgroundColor`, which the Material no longer paints.
- Focus nodes stay borrowed; loading keeps the caller-owned Future model;
  tokens are read on every build; no cached theme values.
- The adoption guard still enforces exactly the documented raw
  `FilledButton`/`OutlinedButton`/`TextButton` exceptions. It does not cover
  `IconButton` (90 constructor sites in `lib/src`), which the documentation
  never claimed.
- `test/typography_boundary_test.dart` expected the small label at 14px; the
  registry's `sm` size is `text-[0.8rem]`, so the expectation now reads
  12.8/22.4. The same test then reaches a pre-existing `DSelect` overflow
  (`Latest topics` exceeds its single line at zoom), which is outside Button.

## Issues

| Issue | Status |
| --- | --- |
| Exterior focus/invalid ring clipped on standalone buttons | fixed in `a7773c7c` |
| Fill painted through the transparent border (no bg-clip-padding) | fixed in `a7773c7c` |
| Fill/border colour changes snapped instead of the 150ms transition | fixed in `a7773c7c` |
| Pressed translation moved only the content, not the surface | fixed in `a7773c7c` |
| Expanded surfaces used the hover colour for every variant and brightness | fixed in `a7773c7c` |
| Focused dark outline replaced its input border with the ring colour | fixed in `a7773c7c` |
| Touch press applied the hover fill on reference variants | fixed in `a7773c7c` (compatibility variants keep it) |
| Loading spinner shrank to 12/14px in xs/sm | fixed in `a7773c7c` |
| `expanded`/`invalid` had no semantics | fixed in `a7773c7c` |
| Inert `DiscourseButtonTheme.focusRingColor` | fixed in `a7773c7c` |
| Button Group section demonstrated with manual radius joins | fixed in `a7773c7c` (documented composition) |
| Stale small-size typography boundary expectation | fixed in `a7773c7c` |
| `DSelect` single-line overflow in `typography_boundary_test` | open (Select owner) |
| `IconButton` outside the adoption guard | open (scope decision) |
| Secondary hover mix in sRGB rather than oklch; no underline offset | intentional (platform limitation) |
| Click cursor, 48px touch targets, compatibility pressed fill | intentional (documented conventions) |

## Verification

```
flutter analyze --no-pub                     # No issues found
(cd profiles/full && flutter analyze --no-pub)   # No issues found
dart format --output=none --set-exit-if-changed <touched files>   # 0 changed
flutter test --no-pub --test-randomize-ordering-seed=random \
  test/d_button_test.dart test/d_button_reference_test.dart \
  test/d_button_adoption_test.dart test/styleguide/button_examples_test.dart \
  test/post_actions_accessibility_test.dart test/typography_boundary_test.dart
```

Results at `a7773c7c`: root and full-profile analysis clean; the button,
example, adoption, post-actions, styleguide-page, Button Group, draft-list,
assignment-sheet and code-block suites pass together (134 tests, seed
87811164). `typography_boundary_test` still fails on the pre-existing
`DSelect` overflow noted above.

The caller sweep ran the 112 test files referencing `DButton` or
`FilledButton` plus `test/styleguide/styleguide_page_test.dart`. Four files
failed because they read `ButtonStyle.backgroundColor`, cast every
`Container` decoration to `BoxDecoration`, or searched for the old ring
`DecoratedBox`; they were updated above. Seventeen other failures were
reproduced unchanged on an export of the base commit `9c4abfed`
(`adaptive_apple_widgets`, `assign_plugin`, `chat_composer`, `d_spinner`,
`diagnostics_panel`, `floating_composer_panel`, `shell_navigation_integration`,
`topic_reading_integration`, `topic_view_lifecycle`, `typography_boundary`)
and are outside this component. `dart format` also reports sixteen untouched
files drifting on that base.
