# Alert Dialog reference and implementation mapping

Reference date: **2026-09-08**

Frozen page: <https://ui.shadcn.com/docs/components/base/alert-dialog>

Frozen Markdown SHA-256: `ccc9147729b395b1d80ba6c9190ffbd5b556213571f958bb10c111a38b63c2da`

The frozen Markdown was downloaded again on 2026-09-09 and matched the
catalogue hash exactly. The base-nova registry item and the linked Base UI
Alert Dialog documentation were inspected as primary sources. The registry
snapshot used during implementation had SHA-256
`974543244faee02eb4ea40264b7e0bbda2b01c3f2c369de965d2ac771c57a8af`;
the linked Base UI Markdown had SHA-256
`b310d7d9465a8fa530b2ba5795026201cb64181d7e901816c5b2096f560b64e1`.

## Acceptance criteria

- Export one generic D-prefixed Alert Dialog family with typed results,
  uncontrolled/controlled state, a borrowed `DDialogController<T>`, trigger,
  content, header, media, title, description, footer, cancel and action parts,
  plus `showDAlertDialog<T>`.
- Compose the reviewed `DDialog<T>` route/focus/lifecycle owner and `DButton`
  action owner. Do not duplicate route, modal, focus-trap or button behavior.
- Match base-nova's black/10 blurred backdrop; 16px viewport margin, grid gap
  and padding; popover surface; foreground/10 exterior ring; xl radius; 100ms
  fade/95%-scale motion; regular 320/384px responsive cap and 320px small cap.
- Match the 16px medium heading, 14/20 muted balanced description, 40px muted
  media tile with 24px artwork, responsive media/header placement, and the
  flush muted/50 bordered 16px footer.
- Keep cancel before action in keyboard focus order. Default narrow footers
  visually reverse into a full-width column; regular wide footers align at the
  logical end; small footers use two equal columns.
- Require an explicit response: outside presses do not dismiss. Escape is an
  explicit cancel request by default and can be disabled. Alert Dialog has no
  ordinary Dialog corner close control.
- Restore trigger/previous or explicit final focus, contain Tab/Shift-Tab,
  expose route title and live errors to assistive technology, preserve DButton
  disabled/loading/focus semantics, and support pointer/touch input.
- Keep caller-owned async work safe: no double submit, no close on failure, no
  late completion closing a later open session, and visible caller-owned error
  text. Generic code performs no account or domain operation.
- Preserve live theme/palette/font/radius/direction/text-scale/reduced-motion
  changes without resetting local state, and avoid overflow at 320px/200% text.
- Demonstrate Composition, Basic, Small, Media, Small with Media, Destructive,
  RTL, controlled state, typed results, disabled/loading/error/retry and async
  ownership with real public widgets and local-only state.
- Audit core and bundled-plugin modals; migrate focused confirmation flows
  while preserving permission, lifecycle, cancellation and persistence guards.

## Visual and behavior mapping

| base-nova / Base UI owner | Flutter owner and mapping |
| --- | --- |
| Root (`defaultOpen`, controlled `open`, `onOpenChange`) | `DAlertDialog<T>` forwards uncontrolled/controlled ownership and typed `DDialogChangeDetails<T>` to `DDialog<T>`. |
| Trigger / external imperative handle | `DAlertDialogTrigger`; caller-created `DDialogController<T>` is borrowed and explicitly disposed by its caller. Calls while detached are ignored. |
| Portal, Backdrop, Viewport | Native `PopupRoute` in `DDialog`: nearest Navigator by default, modal barrier, SafeArea/view insets, closed-loop traversal and live inherited environment. `showDAlertDialog<T>` provides imperative route composition. |
| Popup | `DAlertDialogContent`: surface/ring/radius/padding/gap and exact regular/small responsive caps. There is intentionally no corner X. |
| Header / Title / Description | `DAlertDialogHeader`, `DAlertDialogTitle`, and `DAlertDialogDescription`; centered compact layout, logical-start wide regular layout, route name/header semantics, host font and palette. |
| Media | `DAlertDialogMedia`: 40px muted tile, proportional radius and 24px ambient icon theme; destructive palette and explicit custom colors are supported. Decorative artwork is excluded from duplicate speech. |
| Footer | `DAlertDialogFooter`: flush bordered muted surface; logical wide row, default narrow reverse visual column, and small equal columns. `OrderedTraversalPolicy` retains cancel-first focus independently of visual reflow. |
| Close / Cancel | `DAlertDialogCancel<T>` is the explicit outline close control and returns a typed result. |
| Affirmative action | `DAlertDialogAction<T>` composes `DButton` variants and typed close. `closeOnPressed: false` supports caller-owned work; `controller + onSubmit` adds coalesced submit/close-on-success with an error callback. |
| Focus entry/final focus | The shared Dialog route focuses the first tabbable cancel by default, accepts explicit initial/final nodes, contains keyboard traversal and restores trigger/previous focus. This focused confirmation behavior is the native adaptation of Base UI's interaction-type-aware focus. |
| Dismissal | Outside press is always ignored. Escape closes with `DDialogChangeReason.escape` unless disabled. Explicit cancel/action results remain distinguishable. |
| Motion/live environment | Shared Dialog 100ms fade/scale uses `DMotion`; reduced motion becomes zero duration. Theme, MediaQuery and Directionality are bridged live into an already-open route. |

CSS pixels map one-to-one to Flutter logical pixels at 100% preview scale. The
host palette, font family and radius token replace shadcn's named color/font
variables as required by the project convention.

## Application adoption audit

`showDiscourseAlertDialog<T>` is an application adapter outside the generic
library. It now owns the standard two-choice confirmation composition used by:

- forum/account removal;
- published poll removal;
- draft deletion;
- plugin notification dismissal;
- diagnostics history clearing;
- bookmark destructive changes;
- Voice deep-capture enable/clear;
- topic deletion and selected-post merge/delete;
- group-member removal; and
- Voice room recording start/stop.

The existing callers still own all permissions, site/account lifecycle leases,
controller identity checks, persistence, network mutation, errors and mounted
guards. Confirmation completes before those operations begin.

Retained alternatives are deliberate:

- phrase-entry permanent deletion and group deletion remain specialized form
  dialogs until their editor content is migrated compositionally;
- ordinary channel, event, status, composer, picker and settings editors remain
  Dialog because they do not interrupt solely for a confirmation;
- sheets, drawers, popovers, menus, pickers and full-screen/media surfaces keep
  their separate catalogue owners;
- `DiscourseAlertDialog` and `AdaptiveDialogAction` remain temporarily for
  specialized legacy editor/confirmation bodies not safely expressible by the
  common two-choice adapter; they are no longer the owner for the migrated
  focused confirmations.

## Verification boundary at implementation handoff

Focused widget, styleguide, Dialog dependency and migrated-consumer tests cover
geometry, focus order, explicit dismissal, typed results, async/error behavior,
live route behavior, narrow/200%/RTL/reduced motion, and domain lifecycle guards.
The independent reviewer still owns the first rendered official/native visual
comparison, local-data production fixture, source/kernel/signature evidence,
dependency reconciliation with the accepted Dialog revision, any resulting
fixes, final analysis and local `main` merge.
