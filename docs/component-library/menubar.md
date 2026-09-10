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
- Accepted Dropdown Menu merge:
  `5c6ab6a15d69c7241ab7d9345eb9f6d6418e2787` on local `main`, reviewer task
  `01a085cf-f401-7813-80da-7c687de8a5d5`. The current candidate also integrates
  that owner's prepared `7110ef80` follow-up for focus, RTL glyph direction and
  live registration order; its accepted-main checkpoint remains a merge gate.

## Reference-to-Flutter mapping

| base-nova source | Flutter owner | Exact mapping |
| --- | --- | --- |
| `flex h-8 items-center gap-0.5 rounded-lg border p-[3px]` | `DMenubar` | horizontal `Flex`, 32px minimum border box, 2px gaps, 3px padding, 1px `DTokens.border`, host `lg` radius |
| trigger `rounded-sm px-1.5 py-[2px] text-sm font-medium` | `DMenubarTrigger` | macOS/Linux use the source-exact 24px minimum, host `sm` radius (`base × 0.6`), 6px horizontal / 2px vertical padding, 14px / 20px leading and weight 500; iOS retains the same visible styling in a 48px minimum touch surface |
| `hover:bg-muted aria-expanded:bg-muted` | trigger state surface | live `ThemeData.hoverColor` for hover, press, keyboard focus and expanded state; `AppTheme` derives it against the floating surface so it remains distinct from the bar |
| content `min-w-36`, `rounded-lg`, `p-1`, ring, shadow, 8px side / -4px align offset | `DMenubarContent` + accepted `DDropdownMenuContent` | 144px minimum, host `lg` radius, 4px padding, live popover tokens, 8px / -4px defaults and collision-aware portal |
| item `gap-1.5 rounded-md px-1.5 py-1 text-sm` | `DMenubarItem` | accepted menu row with 6px gaps/padding, 4px vertical padding, host `md` radius (`base × 0.8`), 14px / 20px text and the live menu hover surface |
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
fit all persistent triggers; keyboard focus scrolls the newly focused trigger
fully into view instead of leaving an off-screen command selected.

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
   scrolling without overflow at 200% text and 216–360px preview widths;
   focused triggers are revealed automatically within the scroll viewport.
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

## Independent review corrections

- Preserve the compact 24px desktop trigger inside the 32px root, with a 48px
  minimum trigger hit surface on iOS.
- Remove the example-only width cap and reveal a newly focused trigger before
  opening its popup. The root scrolls only its matching-axis viewport.
- The second native pass found that popup autofocus could hide that trigger
  again in RTL. An embedded Navigator inside a scrolling host reproduced the
  issue: an opened Profiles label moved to x=-275 and a standalone popup moved
  its host page by 86px. Dropdown Menu now owns first-enabled-item focus instead
  of also running Popover's default focus traversal, and item navigation scrolls
  only the popup viewport. Both regressions fail before the fix and pass after.
- Material chevron glyphs already mirror with text direction; selecting the left
  glyph in RTL mirrored twice. The shared Dropdown Menu now uses the directional
  right glyph once, matching the submenu's actual RTL opening direction.
- Menubar triggers and delegated Dropdown Menu rows use the app's menu-specific
  hover surface. The general shell hover token can be effectively identical to
  a floating menu in dark/custom palettes; the menu color is derived against
  that floating surface and preserves the visible separation shown by shadcn.

Source `e3104c9ae1547b90629f85d6e7a7bb97c863f6c7` passes 64 combined randomized
Menubar/Dropdown Menu/Popover/Table component and styleguide tests (seed
1320190751), root/full-profile analysis, and the debug macOS styleguide build.
It incorporates the Dropdown owner's prepared `7110ef80` follow-up, including
Avatar's live-registration-order correction. In a disposable checkout of Context
Menu `dfd02ea4`, both consumer regressions fail on the previous parent (62px host
scroll and mirrored RTL glyph); all 11 Context Menu tests pass with seed 826145
on the combined Dropdown blob `b5c53b46b86b28f8d8a9b6375b4798fdf7c233b6`.
The disposable checkout was removed; its source and tests remain in Git.
The exact-source isolated bundle and signature/kernel identity are recorded in
`evidence/menubar/build-identity.json`.

## Final native and rendered acceptance

The exact `e3104c9a` fixture passed the focused native macOS correction check:

- At 360px and 200% text with reduced motion, End then Down opens Profiles
  with its trigger fully visible in both LTR and RTL. Logical wrapping from
  the open Profiles menu reveals File fully before opening its popup.
- Navigating File down to Print scrolls only the popup; the surrounding page
  and menubar remain stationary. Return selects Print and closes the menu.
- The Plum custom palette works at 360px/200%/RTL with reduced motion.
- Arabic Share shows a left-pointing chevron. Logical Left opens the submenu
  on the left; Right closes only the submenu and leaves the parent open.
- The official rendered dark default, File-open, and With Icons/More-open
  states were compared with native geometry, disabled text, separators,
  shortcuts and destructive icon treatment. Earlier official light and native
  command, checkbox, radio, typeahead and Escape evidence remains valid.

Only the owned isolated app and reference tab were closed, and the desktop
lease was released. Promotion to implemented changes status/acceptance text
only, not the inspected runtime. Native iOS/Linux devices and spoken VoiceOver
were not tested.

The Dropdown owner accepted the shared follow-up in local-main merge
`85f9265bf2593a7edc0693582b7eadf1c6645b8d`, recorded at `d6474006`.
Fresh Menubar candidate `c29732d5` starts from that main pin and passes all 64
focused tests again plus clean root/full-profile analysis. Its Menubar and
Dropdown runtime are identical to the native-inspected source. Main's accepted
Popover joined-control boundary only isolates grouped-control metadata; the
ungrouped Menubar behavior is unchanged. The styleguide overlap only changes
sidebar search focus. All other component rows and workflow metadata were
verified identical to the candidate's main base.
