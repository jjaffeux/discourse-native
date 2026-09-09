# Drawer reference mapping

Captured 2026-09-09 from the frozen official sources.

- shadcn Markdown: `https://ui.shadcn.com/docs/components/base/drawer.md`
  SHA-256 `e3fca4a3433436c5eb043a1075f04d064f97add28e4d89872a9a01fe493cc63a`
- base-nova registry: `https://ui.shadcn.com/r/styles/base-nova/drawer.json`
  SHA-256 `fc81c0adadef868df72172c9cf83237b8ab791a4f0f3e300540883be56c26982`
- Base UI API: `https://base-ui.com/react/components/drawer.md`
  SHA-256 `06e18a642563ba92e71fe756dbadfc3fc8789c9458a37bba6b7b359f3ae8fbcd`

## Exact source-to-Flutter mapping

The base-nova popup uses a 450ms `cubic-bezier(0.22,1,0.36,1)` transform,
popover surface/foreground, a one-pixel border only on the exposed edge, and
the host `xl` radius (`base radius × 1.4`) on that edge. Bottom/top content is
content-sized and capped at viewport height minus 96px. Side content is 75% of
the viewport and becomes 384px at 640px and wider. Header and footer padding is
16px; header title/description gap is 2px and footer action gap is 8px. The
title is 16px medium with heading font; the description/body is 14px with 20px
leading. The optional handle has a 12px-deep hit strip and a 96×4px visual on
the vertical axis, rotated to 4×96px on the horizontal axis.

The overlay is black at 10% plus a 4px backdrop blur. Its opacity follows the
remaining swipe progress, with a 50% minimum while snap points are active.
Overshoot is filled with the popover surface for 48px beyond the drawer edge.
Nested parents use a 16px peek per level, a 5% scale step, 95% brightness and
hidden/faded content while the frontmost drawer owns gestures.

Flutter maps the web route/portal lifecycle to the nearest `Navigator` by
default, live inherited theme/media/direction capture, typed controller state,
focus scopes and route-authorized pops. Gesture movement stays in logical
pixels, uses the Flutter gesture arena, hands a drag from a scrollable only at
its dismiss-facing edge, applies resisted overshoot, and settles with an
interruptible spring. Reduced motion settles immediately. Safe-area and IME
insets replace browser dynamic-viewport and virtual-keyboard CSS variables.

Independent review also checked the pinned Base UI `v1.8.0` implementation,
not only its public API prose. Fraction snap points therefore resolve against
the viewport height before being clamped to the popup extent. Low-velocity
drags choose the closest snap point without projection; projection begins at
0.5 logical pixels per millisecond, and sequential mode advances at most one
detent. A drawer without snap points dismisses only after crossing half its
extent (with a 10px minimum) or reaching that same fast-swipe threshold. Open
snap overshoot uses Base UI's square-root damping. Nested swipe progress and
depth propagate through every mounted ancestor, matching Silk's below-stack
aggregation rather than updating only the immediate parent.

## Silk cross-check

The required `d-sheet` guidance was consulted before implementation. Its exact
source keeps a presented sheet mounted until safe to unmount, represents each
detent with a marker, translates on the travel axis, keeps a bleed background
during overshoot, contains same-axis overscroll, and updates sheets below the
frontmost sheet as one stack. Flutter preserves those state-machine boundaries
with a route that remains mounted through reverse animation, typed snap points,
an interruptible travel controller, scroll-edge notification handoff and an
inherited nested-stack owner. Flutter's spring simulation and gesture arena are
the native adaptations for Silk's sampled spring array and scroll-trap DOM.
