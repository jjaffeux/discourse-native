# Dropdown Menu source evidence

Current shared control styling and application adoption: [2026-09-11 follow-up](control-consistency.md).

Prepared on 2026-09-09 from the frozen 2026-09-08 Base UI/base-nova
reference.

## Reference integrity

- Documentation: `https://ui.shadcn.com/docs/components/base/dropdown-menu`
- Frozen Markdown: `https://ui.shadcn.com/docs/components/base/dropdown-menu.md`
- Frozen Markdown SHA256:
  `3a8ab9398fa074c3cdf023e31bc9368a3b6bafb0b0f146a326eb2c76808ba7fa`
- Registry source:
  `https://ui.shadcn.com/r/styles/base-nova/dropdown-menu.json`
- Registry SHA256 observed on 2026-09-09:
  `335c59dba30145f434a9cc9ccb0438a3c5e2afe857fc11b029de1ecb415224d7`
- Base UI behavior API: `https://base-ui.com/react/components/menu.md`

The frozen Markdown hash was reproduced byte-for-byte before implementation.
The page and registry define Composition, Basic, Submenu, Shortcuts, Icons,
Checkboxes, Checkboxes Icons, Radio Group, Radio Icons, Destructive, Avatar,
Complex, and RTL examples. All are registered as interactive styleguide
examples.

## Reference-to-Flutter mapping

| base-nova source | Flutter mapping |
| --- | --- |
| Popup `min-w-32`, example `w-40`, `p-1` | 128px minimum, 160px example width, 4px content padding |
| Popup `rounded-lg bg-popover text-popover-foreground` | `DTokens.radius × 1`, live `surface` and `foreground` |
| Popup `shadow-md ring-1 ring-foreground/10` | shared `DPopoverContent` two-part medium shadow and layout-neutral 1px exterior 10%-foreground ring |
| Popup `sideOffset=4`, collision-aware positioning | shared `DPopover` placement, flip/shift and safe-area boundary |
| Popup `max-h-(--available-height) overflow-y-auto` | static content when rows fit; one popup-local viewport and scrollbar only after actual vertical overflow |
| Item `gap-1.5 px-1.5 py-1 text-sm rounded-md` | 6px gap/padding, 4px vertical padding, 14/20 text, `radius × .8`, 28px desktop row |
| Mobile accessibility | the same 20px artwork uses an invisible/empty 48px row bound on iOS/Android |
| Label `px-1.5 py-1 text-xs font-medium muted` | 6×4px, 12/16 medium host font and `mutedForeground` |
| Inset `pl-7` | 28px logical start padding, mirrored in RTL |
| Separator `-mx-1 my-1 h-px bg-border` | 1px `DTokens.border` rule extending through the popup padding with 4px vertical gap |
| Shortcut `ml-auto text-xs tracking-widest muted` | logical trailing 12/16 text with 1.2px tracking and muted token |
| Icon slots `[svg]:size-4 gap-1.5` | caller-supplied 16px `IconTheme` slots and 6px gap |
| Destructive focus `destructive/10`, dark `/20` | multiplied live destructive alpha at 10% light / 20% dark |
| 100ms fade/zoom/8px slide | shared `DPopover` animation, removed under reduced motion |
| Checkbox/radio `pr-8`, indicator `right-2` | controlled `checked` semantics, 32px reserved trailing column and a 16px Lucide-proportion check painter |
| Active `accent` / `accent-foreground` | live `hover` / `selectedForeground` pair inherited by labels, icons and shortcuts |
| Submenu `w-auto min-w-[96px] shadow-lg` | 96px reference default with optional intrinsic/larger width, exact two-part large shadow and layout-neutral exterior ring |
| Submenu inline-end placement | nested shared `DPopover`, custom Lucide-proportion directional chevron, mirrored inline placement and keys, `alignOffset=-3` |

The application font remains the configured host font. Public item icon slots
accept widgets rather than coupling the generic component to one icon package.
The styleguide uses Flutter's available outline icons to demonstrate the exact
slot geometry; production callers retain their own app icon vocabulary.

## 2026-09-10 parity follow-up

The live Base UI page and registry were rechecked against the supplied dark
Composition capture. The registry remains byte-identical at SHA256
`335c59dba30145f434a9cc9ccb0438a3c5e2afe857fc11b029de1ecb415224d7`.
The review found that the root menu already matched its 160px example width and
339px content-height arithmetic, but the Flutter submenu incorrectly inherited
that same 160px width. The reference uses `w-auto min-w-[96px]`, and the supplied
Composition submenu resolves to that 96px minimum. `DDropdownMenuSub` now uses
96px by default; richer examples opt into the measured larger width and callers
can request intrinsic sizing with `width: null`.

The same comparison corrected less obvious visual deltas: submenu `shadow-lg`
instead of the root `shadow-md`, a CSS-style exterior ring that no longer steals
one pixel from menu content, active accent foreground propagation into shortcuts
and icons, the full inset even when an icon is present, the checkbox/radio
32px trailing reserve, and component-owned 16px Lucide-proportion check and
directional-chevron strokes.

The content viewport is also now genuinely `auto`: fitting menus do not build a
Flutter `Scrollable` or scrollbar and ignore wheel input. A popup-local
viewport is introduced only after the rows exceed the collision- or
caller-constrained height, preserving access to long menus without making the
ordinary shadcn compositions scroll.

## Acceptance criteria

- Public composition covers Root, Trigger, Content, Group, Label, Item,
  CheckboxItem, RadioGroup/RadioItem, Separator, Shortcut, and nested Sub.
- Controlled/uncontrolled open state, borrowed controller/focus ownership,
  close-on-select policy, controlled checkbox/radio state and callbacks work.
- Return, Space or pointer opening focuses the first enabled actionable row;
  Up/Down/Home/End and repeating typeahead skip disabled rows and wrap.
- Logical submenu arrows open/close in LTR and RTL; sibling submenu ownership
  never overlaps; deepest Escape closes first and restores its trigger; root
  dismissal restores the root trigger.
- Selection, outside pointer, Tab, collision, scrolling, lifecycle suspension,
  live theme/palette/font/radius/direction/text scale and reduced motion use the
  shared Popover lifecycle without a duplicate top-level overlay owner.
- Semantics expose enabled, selected/check/radio, expanded and action state;
  touch platforms have 48px rows without inflating desktop artwork.
- All thirteen frozen documentation examples are interactive and use the real
  public component with local state.
- Table Actions replaces its temporary native `MenuAnchor` while preserving
  its 32px `DButton`, per-row focus lifecycle, expanded-row presentation,
  callback behavior and focus restoration regression.

## Application audit

The reusable `ChoiceMenuAnchor`, `CommandMenuAnchor`, topic category/tag
pickers, search suggestions and large chat/action menus remain specialized
application adapters for now. They own search/filtering, asynchronous busy
state, dynamic permission models, rich rows, category/flair rendering, or
domain-specific keyboard behavior beyond a plain action dropdown. Directly
replacing them during this component source task would erase those behaviors;
their renderers are recorded for a later adapter-by-adapter migration review.

Independent review searched current core and bundled-plugin sources and
inspected the available diagnostics, bookmarks, emoji, Events, Voice and
composer fixtures. Those `PopupMenuButton` call sites are not plain action-menu
substitutions: they preserve multi-select filter state, per-row async/busy
identity, rich emoji previews, recurring-event callback snapshots, participant
permissions and platform-owned editor/gallery behavior. Replacing their trigger
geometry and dismissal model without a dedicated native pass would expand this
review beyond the fixture-backed Table migration, so they remain explicit
adapter follow-ups rather than being hidden or declared migrated. Third-party
package example applications remain outside the product component-library
owner.

The accepted Table styleguide's simple action menu is migrated here because it
has a complete local-data regression fixture. Avatar's pending menu example is
represented by the owning Dropdown Menu Avatar documentation example; Item and
Button Group source-preparation owners were notified of the stable public API
and must reconcile their final compositions after Dropdown Menu is accepted.

## Prepared-parent pin

This isolated branch replayed exact Popover review tree
`d99562f0f6973c9dc3f566eea02d9b00c6de4f7b` as local commit `74684602` on
top of `af91afb9`. It contains Popover implementation `b410f9da` and lifecycle
correction `8281dda2`. Popover is **not accepted** by this evidence. The new
Dropdown Menu reviewer must wait for Popover's accepted local-main merge,
integrate current main, reconcile any Popover API/source differences and rerun
affected menu lifecycle/overlay verification. This prepared parent must never
enter main through Dropdown Menu.

## Review boundary

Source and focused widget verification are prepared. Official rendered
light/dark comparison and isolated native macOS interaction review remain for
the new reviewer under the shared desktop lease. Required native proof includes
opening focus, directional/Home/End/typeahead navigation, check/radio state,
nested focus/non-overlap/deepest Escape, restoration, outside pointer,
positioning/scrolling, and live theme/RTL/scaling/lifecycle updates. No iOS or
Linux device run, spoken VoiceOver pass, or pixel-diff equality is claimed by
the source task.
