# Tooltip audit

Audited 2026-09-09 on `claude/audit-tooltip` against the live reference.

## Reference

| Source | SHA256 |
| --- | --- |
| [Docs page](https://ui.shadcn.com/docs/components/base/tooltip.md) | `d800517217309297330af467d7521ee5fdbc407468bde79fb7945000d1db4b1b` (identical to the frozen `reference/tooltip.md`) |
| [base-nova registry](https://ui.shadcn.com/r/styles/base-nova/tooltip.json) | `2f55867faecee2d3616cfd8c6a80b538909a21e62fdfa2788b1ead56093e5395` (identical to the frozen `reference/tooltip.json`) |
| [base-nova Kbd registry](https://ui.shadcn.com/r/styles/base-nova/kbd.json) | `4cfe2ba8e19f4d19d090eb039e3f1c041c9cfb379ce948237a9b5018203f7a6c` |
| [Base UI Tooltip](https://base-ui.com/react/components/tooltip) (behavior contract, rendered HTML) | `4f4aa0d0d186e6d0e9974c8ad9ae9773734d1b75646721a55461eb7ecb04f50c` |

Implementation: `lib/src/ui/components/d_tooltip.dart`. Examples:
`lib/src/styleguide/examples/tooltip_examples.dart`. Tests: `test/ui_tooltip_test.dart`,
`test/d_tooltip_test.dart`, `test/styleguide/tooltip_examples_test.dart`.

## Comparison

| Part | Reference | Flutter | Status |
| --- | --- | --- | --- |
| Provider | shadcn wrapper `delay = 0`; Base UI `closeDelay` unset, `timeout` 400ms, instant re-open within the timeout | `DTooltipProvider(delay: 0, closeDelay: 0, timeout: 400ms)`, a warm group opens instantly and closes the previous group member | match |
| Trigger delay without a provider | Base UI trigger default 600ms; the shadcn install step mounts a root provider with `delay = 0` | 0ms; `hoverDelay`/`dismissDelay` per trigger | intentional: the installed shadcn default is 0ms for every documented example, so no root provider is required |
| Root props | `open`, `defaultOpen`, `onOpenChange(open, {reason})`, `onOpenChangeComplete`, `actionsRef.close/unmount`, `handle` + `triggerId`, `disabled`, `disableHoverablePopup`, `trackCursorAxis` | `open`, `defaultOpen`, `onOpenChange(open, DTooltipChangeReason)`, `onOpenChangeComplete`, `DTooltipController.show/hide/dismiss`, `controller` + `triggerId`, `disabled`, `disableHoverablePopup`, `trackCursorAxis` | match |
| Trigger props | `closeOnClick` true, per-trigger `disabled`, renders a button; examples use `Button variant="outline"` | `closeOnClick` true, `disabled`, any child; examples use `DButtonVariant.outline` | fixed (examples used primary buttons) |
| Content placement | `side` top, `sideOffset` 4, `align` center, `alignOffset` 0, logical `inline-start`/`inline-end` | same defaults; `DTooltipSide.inlineStart/inlineEnd` resolve by `Directionality` | match |
| Collision | `collisionPadding` 5, flip then shift, `arrowPadding` 5, boundary = clipping ancestors | `collisionPadding` 5, `avoidCollisions` flips then clamps; arrow center clamped 10px from the edges (5px padding for a 10px arrow); boundary = nearest Overlay minus safe areas, trigger clips only decide anchor visibility | match; the boundary choice is the documented fix for the zero-width clipped rail popup |
| Popup box | `inline-flex w-fit max-w-xs gap-1.5 rounded-md bg-foreground px-3 py-1.5 text-xs text-background`, `has-data-[slot=kbd]:pr-1.5`, no border, no shadow | `Wrap(spacing: 6)`, `maxWidth` 320, radius ×0.8, `DTokens.foreground` fill, 12/6 insets, 12px/16px regular, `DTokens.background` text, trailing 6px with `shortcut` or `containsKeycaps`, no border/shadow; measured 28px one-line and 32px keycap body | match; the trailing inset is directional where the registry's `pr-1.5` is physical (intentional: keeps the keycap gap on the keycap side in RTL) |
| Kbd inside content | `bg-background/20` (`dark:` /10), `text-background`, `rounded-sm` | `DKbdTheme` foreground = background, background = background alpha × 0.20 / 0.10, DKbd radius ×0.6 | fixed (alpha was replaced, not multiplied) |
| Arrow | `size-2.5 rotate-45 rounded-[2px]`; top: center 2px above the bottom edge following the anchor; bottom: 2px below the top edge; left/right: `top-1/2!` (popup middle) at `right−1` / `left+1` | 10px rotated `RRect` radius 2; top/bottom follow the anchor; left/right at the popup's vertical middle | fixed (side arrows followed the anchor) |
| Motion | `animate-in fade-in-0 zoom-in-95 slide-in-from-<opposite side>-2` (8px), 150ms `ease`, `origin-(--transform-origin)` = trigger-facing edge plus gap; `animate-out fade-out-0 zoom-out-95` | 150ms `Curves.ease` fade 0→1, scale 0.95→1, 8px slide from the trigger side, pivot on the trigger-facing edge plus `sideOffset`; exit fades and scales only | match |
| Reduced motion | no reference rule | instant open, close and removal under `disableAnimations` | intentional (platform accessibility setting) |
| Hover open/close | `useHover` with a safe polygon while hoverable | innermost-trigger mouse region, pointer bridge polygon between trigger and popup, popup hoverable and scrollable unless `disableHoverablePopup` | match |
| Leave rule | only after the pointer entered the trigger or popup | previously any pointer movement closed a popup opened by a controller, keyboard or parent; now the leave rule applies only once the pointer engaged | fixed |
| `closeDelay` | timer starts on leave and runs to completion | previously restarted by every move outside the pair; now holds its deadline | fixed |
| Keyboard | opens on focus-visible, closes on blur, Escape closes | opens on traditional (keyboard) focus of the child or the `focusable` wrapper, closes on blur unless hovered, Escape closes without blurring | match |
| Escape propagation | `useDismiss` closes the tooltip; other document listeners still run | closes and consumes the key through an early handler | intentional: native layered dismissal; the one observed conflict (compact title editor) was resolved at the caller, see `title-tooltip-follow-up.md` |
| Trigger press | `referencePress` (pointerdown) closes; outside press closes | pointer down on the trigger closes when `closeOnClick`; Enter/Space on the focused trigger also closes; outside pointer down closes | match; keyboard activation closing is intentional (activation is the same intent as a press and the action still runs) |
| Touch | tooltips disabled on touch devices | long press (`touchDelay` 1800ms) or `TooltipTriggerMode.tap`, never invoking the child action | intentional native extension: touch has no hover and iOS is a primary target |
| Scroll / hidden anchor | position tracks the anchor; `data-anchor-hidden` when clipped | popup tracks the anchor each frame; removed when the anchor scrolls out of its clips or overlay; hidden panes (`TooltipVisibility`, `TickerMode`) and app/window deactivation cancel timers and popups | match |
| Multiple open popups | a provider group closes the previous member; without a provider popups can coexist | one visible popup per Overlay | intentional: the installed shadcn default is one root group |
| Semantics | trigger `aria-describedby` → popup `role="tooltip"` | `Semantics(tooltip: message[, shortcut])` on the trigger, popup excluded from semantics and focus; `labelTrigger` merges the name into native IconButton/PopupMenuButton adapters; `excludeFromSemantics` for callers with their own name | match (platform equivalent, bounded to the child) |
| Focus ring of the `focusable` wrapper | no reference (the docs wrap a disabled button in a non-focusable span) | previously 2px inside the child; now 3px `focusRing` at 50% outside the wrapper | fixed; the Tab stop itself is an intentional extension for disabled-control explanations |
| Icon size inside content | no rule (Lucide default) | `IconTheme` 16px | intentional: no documented icon content; 16px matches the button icon scale |
| RTL | logical sides, start/end swap and `alignOffset` sign flip for top/bottom, `dir` on content | same, from `Directionality` | match |
| Examples | Usage, Side, With Keyboard Shortcut (outline icon-sm + `Kbd S`), Disabled Button, RTL (Arabic physical + logical rows) | reproduced with outline `DButton`, `DButton.iconOnly(size: small)` + `DShortcut`, Arabic labels; six additional API examples (alignment, shared delay, controlled, imperative, rich content, cursor tracking/disabled) | fixed (button variants) |
| Listener lifetime | n/a | a global pointer route and early key handler existed per mounted trigger for its lifetime; now only while open or observing a tap | fixed |

## Issues

1. Fixed in 466fe340: a popup opened by a controller, keyboard focus or a
   controlling parent closed on the first unrelated pointer movement.
2. Fixed in 466fe340: a pending `dismissDelay` restarted on every pointer move
   outside the trigger and popup.
3. Fixed in 466fe340: left/right arrows followed the anchor instead of the
   popup middle pinned by the registry's `top-1/2!`.
4. Fixed in 466fe340: keycap tint replaced the background alpha rather than
   multiplying it.
5. Fixed in 466fe340: the `focusable` wrapper ring painted 2px inside the child.
6. Fixed in 466fe340: every mounted trigger observed all pointer and key events
   for its whole lifetime.
7. Fixed in 543c2c09: examples used primary buttons and a non-square label
   button where the reference uses outline and icon-sm buttons.
8. Intentional: 0ms default hover delay without a provider (the shadcn install
   mounts a 0ms root provider).
9. Intentional: Escape is consumed by the open hint; long press/tap on touch;
   one visible popup per Overlay; directional keycap inset; 16px content icons;
   Enter/Space closing the focused trigger's hint; a focus-opened hint staying
   while its control remains focused after a hover leave.
10. Open, outside this component: `test/topic_title_test.dart` "failed inline
    save keeps the edit focused and Escape cancels" and
    `test/shell_navigation_integration_test.dart` "the forum gear opens actions
    below the header" / "shows custom sidebar sections and opens their links"
    fail identically with the previous `d_tooltip.dart`; their assertions are
    about a save error banner, `MenuItemButton` ancestry and a sidebar
    destination, not tooltips.

## Verification

```sh
dart format --output=none --set-exit-if-changed \
  lib/src/ui/components/d_tooltip.dart \
  lib/src/styleguide/examples/tooltip_examples.dart test/ui_tooltip_test.dart
flutter analyze --no-pub
flutter test --no-pub test/ui_tooltip_test.dart test/d_tooltip_test.dart \
  test/styleguide/tooltip_examples_test.dart test/styleguide/styleguide_page_test.dart \
  test/d_button_test.dart test/d_button_adoption_test.dart \
  test/styleguide/kbd_examples_test.dart --test-randomize-ordering-seed=random
```

Format and analysis are clean. The component run passed all 88 tests, seed
2850680539. The five new `ui_tooltip_test.dart` cases fail against the
previous implementation (checked by running them with `main`'s
`d_tooltip.dart` in place).

Caller run (32 files: theme, chat header, composer toolbar, button group,
sidebar, toggle group, forum search/tabs, GIF and reaction pickers, instance
actions, lightbox, topic inbox/progress/title, user menu, Voice call widget,
add-instance sheet, Kbd/Bubble/Message Scroller/Sidebar examples, shell
navigation, chat navigation, content navigation, button reference, emoji
picker, event card, composer upload panel, plugin user menu), seed 26658864:
474 passed, 3 failed; the three failures are the pre-existing cases listed in
issue 10. No shared foundation file changed; `profiles/full` was not
re-analyzed because no export or shared code changed.

Not run: the native app, simulators or browsers. Widget tests with target
platform overrides are not device testing.
