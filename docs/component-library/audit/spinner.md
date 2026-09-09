# Spinner audit

Audited on 2026-09-09 against the live official pages; branch
`claude/audit-spinner`, base `9c4abfed` (local main).

## Reference sources

| Source | SHA-256 |
| --- | --- |
| [Docs page](https://ui.shadcn.com/docs/components/base/spinner.md) | `9c7185da74c70d9b9bb7c3b894e14bb62e2a07c264bed76a786ab7f38325d654` |
| [Registry item](https://ui.shadcn.com/r/styles/base-nova/spinner.json) | `d949d0b91ff34620eecf2bb359536fd3e6942b518dc0a396b77fd02a90661b61` |
| [Button registry](https://ui.shadcn.com/r/styles/base-nova/button.json) | `9ba7e870178813f0552b818a913a2792fb500c779e36395740b4973e3025d427` |
| [Badge registry](https://ui.shadcn.com/r/styles/base-nova/badge.json) | `ccc20021cdcbf0fb23c0d4d28f1da4adde8e51ba59f4b11dd2722ed97a5ee3a4` |
| [Input Group registry](https://ui.shadcn.com/r/styles/base-nova/input-group.json) | `acf9c5497a6c844dee87fbd4afefb6cd8be9ce50d050d14d58a340d955e517a1` |
| [Empty registry](https://ui.shadcn.com/r/styles/base-nova/empty.json) | `e89ffe0fc2969956f6e1d601bd3f00b068600ac08e31590f65344e79ff242230` |
| [Item registry](https://ui.shadcn.com/r/styles/base-nova/item.json) | `eb7167bffffb69a5e808fec2a80923fbf80f594d2f942efa2da1a605fdfd87b7` |
| [Lucide loader-circle](https://unpkg.com/lucide-static@latest/icons/loader-circle.svg) (v1.43.0) | `ebc0ab0a5662fe3f1fae46d910ff26e9e533cfa169813aebc417b567d4e05026` |
| [Lucide loader](https://unpkg.com/lucide-static@latest/icons/loader.svg) (v1.43.0) | `04d0fbdb4e338788ba227fb764cb0f9132553955af2253df80aaa69b5153443f` |
| [Tailwind theme.css](https://raw.githubusercontent.com/tailwindlabs/tailwindcss/main/packages/tailwindcss/theme.css) | `443d7af364200f8ec8352dc78e39485a118a1840d498c97967bf0ae402b39167` |

The docs page and registry bytes are identical to the frozen copies recorded
in `progress.json` and `spinner-reference.md`. The lucide-static files differ
from the raw GitHub copies only by a license comment and a `class` attribute;
the `viewBox`, stroke attributes and paths are identical, and the checked-in
fixture `test/fixtures/spinner/loader-circle.svg` still matches the GitHub
bytes (`043021bb…`).

## Reference to Flutter

The registry component is one element: a Lucide `Loader2Icon` (loader-circle)
with `data-slot="spinner"`, `role="status"`, `aria-label="Loading"` and
`size-4 animate-spin`. There are no variants or cva props; the docs page adds
Customization (LoaderIcon), Size (`size-3/4/6/8`) and compositions.

| Part | Reference | Flutter | Result |
| --- | --- | --- | --- |
| Artwork | `viewBox 0 0 24 24`, `M21 12a9 9 0 1 1-6.219-8.56`, `fill=none`, `stroke=currentColor`, width 2, round caps and joins | Same SVG string through `flutter_svg`; `strokeWidth` in view-box units; raster comparison with the fixture in `d_spinner_test.dart` | match |
| Default size | `size-4` = 16px | `DSpacing.lg` = 16, `SizedBox.square` | match |
| Size example | 12 / 16 / 24 / 32, `gap-6` = 24px | `DSpinner(size: 12 / 24 / 32)` and default, `Wrap(spacing: 24)` | match |
| Color | `currentColor` from the surrounding text color | Inherited `IconTheme` color, then `DTokens.foreground`; explicit `color` | match (Flutter icons carry color through IconTheme, which every composition owner sets) |
| Motion | `animate-spin`: `spin 1s linear infinite`, 0→360° | `DMotion.spin` = 1s, linear `AnimationController.repeat`, `RotationTransition`, direction-independent | match |
| Motion while unfocused | Keeps spinning while the page is visible | Was frozen on `AppLifecycleState.inactive` (any non-key desktop window); now keeps turning; hidden/paused frames are stopped by the scheduler | fixed |
| Reduced motion | No `motion-reduce` variant; keeps spinning | Pauses at the current angle when `MediaQuery.disableAnimations` is set, busy semantics unchanged | intentional (see below) |
| Semantics | `role="status"` (implicit polite live region), `aria-label="Loading"` | `SemanticsRole.loadingSpinner` + `liveRegion: true` + label `Loading`; `semanticLabel: null` makes it decorative | intentional (see below) |
| Focus and pointer | Inert SVG (`pointer-events-none` in every host) | `IgnorePointer`, `ExcludeFocus`, `ExcludeSemantics` on the artwork | match |
| Customization | `LoaderIcon` (eight 2-unit radial strokes) replaces the arc | Exact Lucide loader SVG as `child`; inherits size and color | match |
| Button | `size="sm"` disabled default/outline/secondary, `<Spinner data-icon="inline-start" />`: h-7, `pl-1.5` inside a 1px border, `gap-1`, spinner keeps its own `size-4`, `opacity-50` | `DButton(size: small, icon: DSpinner(semanticLabel: null), variant: primary / outline / secondary, onPressed: null)`: 28px, 7px inset, 4px gap, 16px spinner, 50% opacity (pinned by test) | fixed (examples used a re-themed private button) |
| Badge | `[&>svg]:size-3!` forces 12px, `gap-1`, `pl-1.5` with an inline-start icon, default/secondary/outline | `DBadge(leading/trailing: DSpinner(size: 12, semanticLabel: null))`, 4px gap, 6px inset | match |
| Input Group | `InputGroupAddon` is `text-muted-foreground` with `[&>svg]:size-4`; inline-end on a disabled input, block-end with `Validating...` and an `ml-auto` default `InputGroupButton` with `ArrowUpIcon` | `DInputGroupAddon` IconTheme tints the 16px spinner muted (pinned by test); block-end row with status and `DInputGroupButton.icon(variant: primary)` using the exact Lucide ArrowUp at 14px | fixed (explicit muted color and a Material arrow replaced) |
| Empty | `EmptyMedia variant="icon"`: 32px `bg-muted rounded-lg` box, spinner keeps `size-4`; title, `text-sm/relaxed` muted description, `Button variant="outline" size="sm"` Cancel | `DEmptyMedia(variant: icon, child: DSpinner())`, `DEmptyTitle`, `DEmptyDescription`, `DButton(variant: outline, size: small)` | fixed (example used a private Container composition) |
| Item demo | `Item variant="muted"` in `max-w-xs`: `bg-muted/50`, 1px transparent border, `px-3 py-2.5`, `gap-2.5`, `ItemMedia` default, `ItemTitle line-clamp-1`, second `ItemContent` `flex-none` with `text-sm tabular-nums` | `DItem(variant: muted)` at 320px with `DItemMedia(child: DSpinner())`, `DItemTitle`, second `DItemContent` with tabular figures; spinner at 13px from the edge, amount ending 13px before it (pinned by test) | fixed (example used a private Row) |
| Item `[--radius:1rem]` and Badge `[--radius:1.2rem]` | Demo-local radius overrides | App radius token through `DTokens.radius` | intentional: the theme radius is app-owned (visual-fidelity.md) |
| RTL | `useTranslation` selector (en / ar / he) sets `dir` on the wrapper and the Item | `DSelect` language selector and `DDirection`; Arabic and Hebrew strings from the docs page | fixed (previously followed the preview direction only, no Hebrew) |
| Usage | `import { Spinner }`; `<Spinner />` | `package:discourse_native/discourse_ui.dart`; `const DSpinner()` | match |

## Implementation review

- Lifecycle: the `WidgetsBindingObserver` is gone. `SchedulerBinding`
  disables frames for hidden, paused and detached states, so the observer only
  ever changed behavior for `inactive`, where it contradicted the reference.
  The explicit `TickerMode` check was redundant with
  `SingleTickerProviderStateMixin`, which mutes the ticker; the test still
  asserts zero transient callbacks under a disabled ticker subtree.
- No animation controller or ticker leaks: the controller lives in the
  private artwork state and is disposed with it; the outer widget is stateless.
- No theme values are cached: color and the reduced-motion preference are read
  in `build`, and the open-dialog test asserts a palette change reaches the
  spinner without replacing its animation.
- `strokeWidth` is inert when `child` is supplied; this is documented on the
  property (custom artwork owns its strokes).
- Tight constraints scale the artwork both down and up (`FittedBox`
  contain). Fifteen app call sites wrap a default spinner in an 18–22px
  `SizedBox.square` that was migrated from Material indicators, so this
  documented behavior is retained.
- Semantics are bounded to the spinner node; the artwork subtree is excluded,
  and `semanticLabel: null` yields no node at all.

## Issues

1. Fixed in `88574e15`: motion froze whenever a desktop window lost key
   status (`AppLifecycleState.inactive`); the reference keeps spinning while
   visible.
2. Fixed in `88574e15`: the Button, Empty and Item (demo and RTL) examples
   reproduced the reference with private compositions instead of the accepted
   `DButton`, `DEmpty` and `DItem` owners; the Input Group example set an
   explicit muted color the addon already supplies and used a Material arrow.
   The RTL example lacked the reference language selector and Hebrew strings.
3. Fixed in `88574e15`: `loading button spinner inherits its variant color`
   failed on main because `DButton` animates its icon color for 150ms between
   variants; the test now lets that transition finish.
4. Intentional: reduced motion pauses the rotation. The reference has no
   `motion-reduce` variant, but conventions.md requires honoring the platform
   Reduce Motion preference; the adaptation is narrow (only under that
   preference) and keeps the busy semantics and artwork.
5. Intentional: `SemanticsRole.loadingSpinner` with `liveRegion: true`
   instead of `SemanticsRole.status`. Flutter's semantics validator rejects a
   live region on the `status` role, and the iOS/macOS/Android bridges announce
   from the live-region flag, not from the role, so this is the mapping that
   reproduces `role="status"` behavior natively.
6. Open, for the Button owner (`claude/audit-button` is in flight):
   `DButton`'s own `loading` indicator uses the button's icon size
   (`spacingUnit`, 14px for `small`, 12px for `extraSmall`), while the docs'
   Button composition keeps the spinner at 16px in every size because
   `Spinner` carries its own `size-4` class. `lib/src/ui/components/d_button.dart`
   line 769 (`DSpinner(size: spacingUnit, …)`) would need `const DSpinner(…)`
   to match; not changed here to avoid conflicting with that audit and because
   it alters app callers' compact loading buttons.
7. Open, pre-existing and unrelated: `native_inline_video_playback_test.dart`
   (3 tests) and `chat_composer_test.dart` (image attachment thumbnail size)
   fail identically with main's Spinner sources restored (seed `281055177`).

## Verification

Flutter 3.47.2. `flutter pub get --enforce-lockfile` at the root; no lockfile
or pin changes.

- `dart format --output=none --set-exit-if-changed lib/src/ui/components/d_spinner.dart lib/src/styleguide/examples/spinner_examples.dart test/d_spinner_test.dart test/styleguide/spinner_examples_test.dart` — 0 changes.
- `flutter analyze --no-pub` — no issues.
- `flutter test --no-pub test/d_spinner_test.dart test/styleguide/spinner_examples_test.dart --test-randomize-ordering-seed=random` — seed `843774326`: 33 passed, 3 failed; the three were example-test expectations corrected in the same commit (the Item's 1px border offset and the touch-platform tap target). Re-run of `test/styleguide/spinner_examples_test.dart`: 20 passed, seed `3288685427`.
- `flutter test --no-pub <29 test files referencing DSpinner, including both Spinner files> test/styleguide/styleguide_page_test.dart --test-randomize-ordering-seed=random` — seed `281055177`: 627 passed, 4 failed; the 4 failures are issue 7 and reproduce with main's Spinner sources.
- `flutter test --no-pub test/gif_picker_test.dart test/draft_list_test.dart test/lightbox_test.dart test/d_input_group_test.dart test/d_item_test.dart test/styleguide/button_examples_test.dart test/styleguide/empty_examples_test.dart test/styleguide/item_examples_test.dart --test-randomize-ordering-seed=random` — seed `3929612053`: 112 passed.

No shared foundation file was changed. The native app, simulator and browser
were not run; this is a source-level audit backed by widget tests.
