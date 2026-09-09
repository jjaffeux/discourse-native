# Popover reference and native mapping

Reference date: 2026-09-08. The frozen component page is
`https://ui.shadcn.com/docs/components/base/popover.md`, SHA256
`833273ce2ef2e83164a1824c0e6151452d4fc5f7d602c4871f9705bdef163587`.
It was fetched again byte-for-byte on 2026-09-09. The implementation registry is
`https://ui.shadcn.com/r/styles/base-nova/popover.json`, SHA256
`ba5fe84f353f6c0fd2133a2ab893f5e8861fc60dc4dea548a7ec875acaa37b2c`.
The inspected Base UI behavior/API source is
`https://base-ui.com/react/components/popover.md`, SHA256
`e50617eaad64fbc205f0ff730bb60001f9152e319a24c4d08e9cdc154cc863bf`.

## Measured translation

| base-nova source | Flutter mapping |
| --- | --- |
| `w-72` | `DPopoverContent.width`, default 288 logical pixels; collision constraints reduce this for narrower bounds. |
| `p-2.5`, `gap-2.5` | 10px content padding and documented composition gap. Header uses the source's `gap-0.5`, 2px. |
| `rounded-lg` | `DTokens.radius × 1.0`; the live host radius remains the shadcn `lg` base. |
| `bg-popover`, `text-popover-foreground` | Live `DTokens.surface` and `foreground`, including while the overlay is open. |
| `text-sm` | Host-family text at 14px, 20px leading, weight 400, zero tracking. Title merges weight 500; description uses `mutedForeground`. Text scaling remains inherited. |
| `ring-1 ring-foreground/10` | A 1px surface border using the existing foreground alpha multiplied by 10%; it does not tint the surface interior. |
| `shadow-md` | Two Flutter shadows matching Tailwind's 0/4/6/-1 and 0/2/4/-2 layers at black 10%. |
| `sideOffset=4`, `alignOffset=0` | Logical-pixel defaults on `DPopoverContent`. |
| `duration-100`, `fade`, `zoom 95`, side slide 2 | 100ms ease fade/0.95 scale and an 8px side-aware slide around the anchor-facing transform origin. Reduced motion completes in one frame. |

The public owner is `DPopover`, composed with `DPopoverTrigger`,
`DPopoverContent`, optional `DPopoverAnchor`, `DPopoverHeader`,
`DPopoverTitle`, `DPopoverDescription`, and `DPopoverClose`. Trigger and close
use builders so a nested `DButton` remains the only semantic action and retains
its focus node, hover, press and disabled behavior. `DPopoverController` can be
borrowed; calls while unmounted are ignored and the popover never disposes a
borrowed controller or focus node.

Top, bottom, left, right and direction-aware inline sides support start, center
and end alignment plus independent offsets. Side and alignment collision policy
can flip, shift or remain uncorrected inside a safe-area or caller rectangle.
A paint-transform tracker refreshes an open overlay only when its anchor moves
or changes size, covering scroll/layout/animation without running a perpetual
ticker. Content gets a bounded native scroll owner when large text or collision
space makes it taller than the available side.

Keyboard activation enters the first nested focusable control. Touch activation
focuses the popup scope rather than summoning a field keyboard. Escape, outside
press, a composed close action, trigger activation, lifecycle loss, trigger
removal and the controller can dismiss; focus returns to the trigger or the
previous focus owner. The popup is a named explicit semantic container while
nested fields and buttons keep independent nodes and bounds.

## Examples and application audit

The styleguide reproduces Basic, start/center/end Align, With Form, and RTL
examples. It adds controlled close/reason reporting, all physical and logical
sides, custom moving anchor, collision, narrow/large-text, live-theme and
reduced-motion coverage. With Form now composes the merged `DInput` owner and
Flutter `Form`; richer label/description/error layout remains with the separate
in-progress Field owner, so no substitute component owner was introduced.

The topic header's plugin-property details surface is a genuine rich popover and
now uses `DPopover` on pointer platforms. Its current topic store and plugin
listenables remain live while open, navigation invalidation still dismisses it,
plugin-owned action callbacks/permissions remain untouched, and iOS/Android keep
the existing touch sheet. This fixture includes Assign's people/groups,
notes/status and management actions when the plugin supplies them.

`showAnchoredPicker` category/tag/time-range/assignment pickers,
`ChoiceMenuAnchor`, `CommandMenuAnchor`, `MenuAnchor`, `PopupMenuButton`, Select,
Combobox, Hover Card, navigation menus, dialogs and Tooltip are retained. They
own selection or command keyboard semantics, result futures, large-list search,
touch-sheet adaptation, modal behavior or hover-only behavior that a generic
rich popover must not absorb. Tooltip and those pending menu owners have similar
collision geometry; consolidation is deferred to the final library audit after
their public APIs exist rather than creating a cross-owner dependency here.

## Verification boundary

Widget tests cover controlled/uncontrolled state, imperative lifecycle, distinct
dismissal reasons, keyboard and touch focus entry, restoration, independent
semantics, live theme, exact default gap/alignment, RTL, collision flip, narrow
large text, reduced motion, anchor movement, safe removal, styleguide examples,
native Form behavior, and the real topic-header migration's live data/navigation
dismissal. Native and reference-rendered inspection remains queued for the
serialized desktop slot; widget tests do not claim VoiceOver or device parity.
