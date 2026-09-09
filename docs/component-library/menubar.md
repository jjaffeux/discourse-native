# Menubar implementation record

## Frozen reference

- Catalogue date: 2026-09-08.
- Documentation: <https://ui.shadcn.com/docs/components/base/menubar>
- Frozen Markdown: <https://ui.shadcn.com/docs/components/base/menubar.md>
- Frozen Markdown SHA-256: `8ae4486c307453e61359a37284084facbfbc6495ed0dabdc47ad991a06f734ae`
  (verified byte-for-byte again on 2026-09-09).
- Primary base-nova registry: <https://ui.shadcn.com/r/styles/base-nova/menubar.json>
- Registry response SHA-256: `265f030bd11d52072325f749bfd2c8070a9a1cc48098aa3fb245b2460801e6cd`.
- Primitive API: <https://base-ui.com/react/components/menubar#api-reference>
  (read on 2026-09-09). The root documents `loopFocus: true`,
  `disabled: false`, `orientation: horizontal` and `modal: true`.
- Prepared Dropdown Menu source pin:
  `d273c27e788bb3991c773c7432e0b8c927715651` on
  `codex/review-dropdown-menu-candidate`, reviewer task
  `01a085cf-f401-7813-80da-7c687de8a5d5`. This is tested preparation,
  not accepted parent evidence; final Menubar review is gated on the accepted
  Dropdown Menu merge in local main.

## Reference-to-Flutter mapping

| base-nova source | Flutter owner | Exact mapping |
| --- | --- | --- |
| `flex h-8 items-center gap-0.5 rounded-lg border p-[3px]` | `DMenubar` | horizontal `Flex`, 32px minimum border box, 2px gaps, 3px padding, 1px `DTokens.border`, host `lg` radius |
| trigger `rounded-sm px-1.5 py-[2px] text-sm font-medium` | `DMenubarTrigger` | host `sm` radius (`base × 0.6`), 6px horizontal / 2px vertical padding, 14px / 20px leading, weight 500 |
| `hover:bg-muted aria-expanded:bg-muted` | trigger state surface | live `DTokens.muted` for hover, press, keyboard focus and expanded state |
| content `min-w-36`, `rounded-lg`, `p-1`, ring, shadow, 8px side / -4px align offset | `DMenubarContent` + accepted `DDropdownMenuContent` | 144px minimum, host `lg` radius, 4px padding, live popover tokens, 8px / -4px defaults and collision-aware portal |
| item `gap-1.5 rounded-md px-1.5 py-1 text-sm` | `DMenubarItem` | accepted menu row with 6px gaps/padding, 4px vertical padding, host `md` radius (`base × 0.8`), 14px / 20px text |
| `data-inset:pl-7` | item/label/sub-trigger `inset` | 28px logical start padding, mirrored in RTL |
| checkbox/radio indicator `absolute left-1.5 size-4` | leading `_MenubarCheckIcon` slot | exact 16px leading reservation and 2px round-cap check artwork; unchecked rows retain alignment |
| destructive focus opacity 10% light / 20% dark | destructive item variant | multiplicative live destructive-token alpha through the accepted menu surface |
| shortcuts `text-xs tracking-widest text-muted-foreground` | `DMenubarShortcut` | 12px caption metric, 1.2px tracking, live muted foreground |
| submenu content `min-w-32`, inline side animation | `DMenubarSub` + `DMenubarSubContent` | 128px reference minimum intent, logical inline placement, mirrored chevron, single sibling submenu and deepest-first Escape |

Flutter's overlay/focus owners replace browser portal mechanics. `DMenubar`
adds the distinct top-level coordination that Dropdown Menu does not own:
logical arrow roving, Home/End, Enter/Space/ArrowDown opening, menu switching
from an open popup or pointer hover, one-open-menu ownership and final trigger
focus restoration. Individual popup typeahead, item roving focus, disabled
skipping and nested submenu boundaries remain with Dropdown Menu. The horizontal
root becomes internally scrollable when large text or a narrow viewport cannot
fit all persistent triggers; it does not shrink or clip command labels.

The Base UI `modal` browser prop is not exposed as a decorative boolean. The
accepted Flutter Dropdown Menu lifecycle owns outside-pointer dismissal, Escape,
focus scope and overlay ordering consistently for all in-app menus. Application
menu-bar integration with macOS/iOS/Linux system APIs is intentionally outside
this generic in-app component.

## Documented examples and acceptance

The styleguide provides the frozen Composition/full demo, Checkbox, Radio,
Submenu, With Icons and Arabic RTL examples. It uses real `DMenubar` public
primitives and the exact Lucide File, Folder, Save, Settings, Circle Help and
Trash paths under the repository's Lucide license. Examples keep all mutable
state local and cover disabled, inset, shortcut, checked, radio, destructive,
nested and selected behavior.

Focused acceptance criteria:

1. Root and trigger geometry remain source-exact at 100% text while growing or
   scrolling without overflow at 200% text and 216–260px preview widths.
2. Arrow navigation follows logical direction in LTR/RTL; Home/End and disabled
   skipping preserve roving focus, and an open popup switches as a unit.
3. Checkbox/radio selection updates native semantics without closing by default;
   ordinary actions close the full chain and restore the top-level trigger.
4. Submenu arrows mirror in RTL, sibling submenus close, and Escape dismisses
   only the deepest active popup before the top-level popup.
5. Open surfaces rebuild from live light/dark/custom `DTokens`, live font/radius,
   reduced motion and inherited text scaling.
6. Independent review compares the official rendered reference and the real
   styleguide on macOS under the shared desktop lease before promotion from
   baseline to implemented.

## Application adoption audit

No production in-app surface currently presents a persistent row of two or more
independent command-menu triggers, so no faithful Menubar migration was made.
The audit covered core shell and plugin `MenuAnchor`, `PopupMenuButton`,
`SegmentedButton`, `DTabs`, calendar toolbar and command-palette usages:

- Composer, topic/post, instance, user, diagnostics, forum-tab, emoji, event,
  chat, poll and voice popup actions are single-trigger contextual/dropdown
  menus. They belong to Dropdown Menu or Context Menu adoption, not Menubar.
- Diagnostics, move-posts, update-channel, settings and event-calendar segments
  choose one mode/filter. They remain segmented controls rather than command
  menus.
- Forum/group/chat information tabs and route navigation remain tabs/navigation;
  converting them because they are horizontal would change their semantics.
- The event calendar's period navigation is a toolbar of immediate commands and
  view selectors with responsive wrapping, not a row of popup menu categories.
- Native application/OS menus were not changed. The generic widget contains no
  Discourse service, store, route or networking ownership.

These retained alternatives are specific; future product surfaces that add a
persistent File/Edit/View-style in-app strip should adopt `DMenubar` directly.
