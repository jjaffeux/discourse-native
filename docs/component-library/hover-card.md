# Hover Card

## Frozen source

- Catalogue reference: `https://ui.shadcn.com/docs/components/base/hover-card`
- Markdown: `https://ui.shadcn.com/docs/components/base/hover-card.md`
- Captured 2026-09-08 SHA-256: `8f30193c745aaf270cdf63043ca452cdffb895e8643a86c662ca0804c6022dc8`
- Verified again 2026-09-09: the downloaded Markdown has the same SHA-256.
- Primary registry: `https://ui.shadcn.com/r/styles/base-nova/hover-card.json`
- Primary behavior/accessibility reference: `https://base-ui.com/react/components/preview-card`

The frozen page contains Usage, Composition, Trigger Delays, Positioning,
Basic, Sides, RTL and API Reference. The styleguide reproduces each of those
compositions with the merged Button and Avatar owners.

## Reference mapping

CSS pixels map one-to-one to Flutter logical pixels at 100% text scale.

| Base Nova source | Flutter mapping |
| --- | --- |
| `w-64` | `DHoverCardContent.width = 256` |
| `p-2.5` | 10px content padding |
| `text-sm` | 14px, 20px leading, host font family |
| `rounded-lg` | `DTokens.radius` (the host-relative lg radius) |
| `bg-popover`, `text-popover-foreground` | `DTokens.surface`, `DTokens.foreground` |
| `ring-1 ring-foreground/10` | one-pixel foreground ring at multiplied 10% alpha |
| `shadow-md` | 0/4/6/-1 and 0/2/4/-2 shadows at black 10% |
| default `side="bottom"`, `sideOffset=4` | bottom and 4 logical pixels |
| default `align="center"`, `alignOffset=4` | centered plus four logical pixels; vertical-axis offsets mirror in RTL |
| 100ms fade, zoom 95%, directional slide `2` | 100ms fade/0.95 scale/eight-pixel directional slide |
| Base UI trigger delay 600ms / close delay 300ms | identical defaults; each trigger can override both durations |

`DPopoverSide` and `DPopoverAlign` are shared with the accepted Popover owner,
including physical top/bottom/left/right, logical inline-start/inline-end,
start/center/end alignment, flipping, shifting, custom offsets, safe-area bounds
and an optional collision rectangle. The implementation keeps the accepted
Popover lifecycle, Escape ownership and layer behavior unchanged.

## Interaction and accessibility

Base UI describes Preview Card as a visual progressive enhancement. The
destination trigger is the only accessible interface; exposing supplementary
preview contents would repeatedly interrupt screen-reader navigation. Flutter
therefore keeps the caller's real button/link semantics and activation, opens
immediately for traditional keyboard focus, never moves focus into the card,
and closes on blur, trigger activation, outside press or topmost Escape.

Mouse hover uses the configured timers. A polygonal bridge between the trigger
and positioned surface keeps the card open across its gap, and entering the
content cancels close. Visible text remains selectable and tall/narrow content
scrolls, but the content subtree is excluded from focus traversal and assistive
semantics. Touch and pen activation continue directly to the trigger and do not
open an inaccessible preview. Rapid movement between separate preview triggers
cancels stale opening timers and hands the visible layer to the latest trigger.
Lifecycle suspension, view-focus loss, disable, anchor removal, controller
replacement and disposal cancel timers and remove overlays safely.

Controlled `open` state is authoritative. `DHoverCardController` controls one
mounted card imperatively, ignores calls while detached, and is never disposed
when borrowed. `onOpenChange` reports hover, focus, trigger press, outside
press, Escape, imperative and lifecycle reasons; completion follows the actual
100ms transition. Open overlays rebuild from inherited theme, direction,
text-scale, radius and reduced-motion values.

The frozen shadcn page sends its API Reference to Base UI, whose current
reference explicitly documents multiple triggers, typed trigger payloads and
controlled trigger IDs. `DHoverCardGroup<T>` therefore provides one Flutter
root for two or more `DHoverCardGroupItem<T>` triggers, an unconstrained layout
builder, strongly typed payload content, controlled/uncontrolled open and
trigger-ID state, and immediate handoff while a group is already open. Detached
DOM triggers and Base UI's optional animated content viewport are not copied:
Flutter callers keep the root around an arbitrary trigger layout, the existing
controller covers detached imperative open/close for a single trigger, and the
group updates its one visible payload without adding a second transition API.

Independent review fixed three source issues before acceptance: immediate
animation values no longer report duplicate completion callbacks, controller /
focus-node replacement and disabling no longer mutate an OverlayPortal during
the persistent build phase, and an already scheduled close is cancelled and
rechecked when the pointer enters the trigger-to-content bridge.

## Application adoption

`UserCardTarget` is the suitable current core adoption. Hover or keyboard focus
loads the existing cached user-card model through the application-owned
`ShellController` and presents a read-only name, username, avatar, title and
location preview. The generic Hover Card imports no shell model or service.
Existing click, touch, Enter and Space behavior still opens the full user-card
route with its actions, permissions, plugin contributions and navigation.
Authenticated avatar loading remains in `AvatarImage`, composed inside the
generic `DAvatar` frame.

The following alternatives deliberately remain:

- `HoverPanel` for reaction pickers, liker/reactor panels and their touch
  sheets. Those surfaces contain essential focusable actions, selection and
  mutation and therefore conflict with Base UI's non-navigable preview model.
- The full user-card dialog remains the click/touch destination. It contains
  profile/plugin actions, cooked links, retry behavior and route focus, none of
  which belongs in supplementary Hover Card content.
- Composer/chat/topic previews are persistent inline application content, not
  hover-triggered destination previews. Tooltip remains for concise labels and
  shortcuts rather than rich destination summaries.

No current generic link-preview cache exists outside user cards. Adding network
fetching to the component or inventing a second application cache was rejected.

## Acceptance fixture

The styleguide Basic, Composition, Trigger Delays, Positioning, Sides and RTL
examples are self-contained and use real public widgets. A Multiple Triggers
and Payloads example covers the API-reference composition. The independent
reviewer must perform the first official browser render comparison and native
macOS inspection under the shared desktop lease, including the Basic reference,
all sides, dark/custom theme, narrow 200% text, Arabic RTL, reduced motion,
pointer gap travel, keyboard focus/Escape, touch route preservation and the real
`UserCardTarget` loading/ready/error behavior. Widget tests and successful
builds are evidence, but do not satisfy that native inspection requirement.
