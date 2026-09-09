# Item implementation and independent review

Task `01a084bf-dd8a-7c13-86dd-63f2e60d20cd`, branch `codex/ui-item`,
initial base `402fe578`; integrated pinned main
`e612ad7b47413fa890b35ae3b55a6f6d37b08cf7` in merge `1462873c`.
All 17 merged component owners, coordinator Group/Sidebar/Topic Inbox fixes and
every non-Item progress row are preserved. Only Item progress metadata belongs to this task.
Independent reviewer task `01a08558-aec4-7591-ac85-682a1eae4290` merged the
implementation branch with history, compared the frozen reference in a live
browser, inspected the exact-source macOS fixture, and fixed the only observed
Item defect. The final candidate composes Dropdown Menu from its accepted main
merge `5c6ab6a15d69c7241ab7d9345eb9f6d6418e2787`.

## Source evidence

Retrieved 2026-09-09 using HTTPS reads, without browser or application control:

- `https://ui.shadcn.com/docs/components/base/item.md` — SHA256
  `c4a69c25199741ad3baea25f07a869e1aebf08cf3274f1a4f2e9da04afbbe0f0`,
  exactly the frozen catalogue hash. All documented example code is in this file.
- `https://ui.shadcn.com/r/styles/base-nova/item.json` — SHA256
  `eb7167bffffb69a5e808fec2a80923fbf80f594d2f942efa2da1a605fdfd87b7`.
- Copies: `reference/item/item.md`, `reference/item/item.json`.
- `reference/item/artwork.json` records original URL, bundled path and SHA256
  for every Lucide SVG, avatar, generated song artwork and model photograph.
  Unsplash credits: Valeria Reverdo (sm), Michael Oeser (lg), Cherry Laithang
  (mini). No example needs a live image request.

## CSS-to-Flutter mapping

All units below are logical pixels at 16px rem and 100% text scaling. The
reviewer confirmed these source-derived metrics against the live official Base
UI page and the native fixture.

| Source | Flutter |
| --- | --- |
| Root `rounded-lg border text-sm` | 1px border-box inset, radius = live host radius, 14px base font, host font family |
| Default/sm `gap-2.5 px-3 py-2.5` | 10px gap, horizontal 12px and vertical 10px padding plus 1px border; identical for these sizes |
| xs `gap-2 px-2.5 py-2` | 8px gap, horizontal 10px/vertical 8px plus border |
| `border-transparent` / `border-border` | Transparent or live `DTokens.border` |
| `bg-muted/50` | `tokens.muted` with existing alpha multiplied by .5 |
| Link hover `bg-muted`, duration 100 | Live muted hover, 100ms color transition, zero with reduced motion |
| Focus border + `ring-[3px] ring-ring/50` | Live focus border; outside-only 3px rounded DRRect, existing ring alpha multiplied by .5 |
| Group gap4 / sm gap2.5 / xs gap2 | 16 / 10 / 8; tightest direct child size, or explicit group size for wrapped app rows |
| ItemSeparator `my-2` | Existing DSeparator 1px rule with 8px margin above/below; group gap remains additive |
| Icon media svg size4 | 16px IconTheme; examples use original Lucide SVG paths/stroke, not Material approximations |
| Image size10 / sm size8 / xs size6, rounded-sm | 40 / 32 / 24px square clipping, host radius × .6; child supplies cover fit |
| Described media `self-start translate-y-0.5` | Layout aligns media at body start +2px without increasing row height |
| Content flex1 / adjacent content flex-none | First direct DItemContent gets remaining width; subsequent content keeps natural bounded width |
| Content gap1 / xs gap0 | 4 / 0px |
| Title `text-sm leading-snug font-medium line-clamp-1` | 14px, 1.375 leading, weight500, one line at ordinary scale |
| Description `text-sm leading-normal font-normal line-clamp-2`, xs text-xs | 14 / 12px, 1.5 leading, weight400, live muted foreground, two lines |
| Actions gap2 | 8px horizontal and reflow gap; independent interactive descendants |
| Header/footer basis-full, justify-between, gap2 | Full-width named slots; child owns its Row/Wrap with 8px gap or its image |

Native adaptations are narrow and explicit:

- DItem uses named header/footer slots and direct typed body parts instead of
  CSS descendant selectors. Group `size` and `spacing`, content `spacing`,
  root `padding`, and description `height` express example class overrides.
- `avatar` is a convenience media spelling (the prose mentions it, but registry
  media variants are default/icon/image). Like default it preserves Avatar size.
- Reference descriptions use text-left; Flutter uses logical start for RTL.
  At text scaling above 150%, title/description clamps relax. At body widths
  below 160px, or when siblings leave less than 64px for content, the row stacks.
  Large text also stacks. Child elements keep identity through this reflow.
- No intrinsic measurement is used; the single render owner measures row
  children and places them. This supports AvatarGroup/caller LayoutBuilders
  and keeps app lazy list construction outside the generic ItemGroup.
- Touch-platform interactive rows retain a 48px minimum; desktop retains source
  compact bounds. Native action rows also use hover, like reference links.
- `onPressed` and `link` express render-as-action/link. URL routing, permissions,
  selection, async mutations and external opening policy remain in callers.
  Return/Space activate only the row's primary focus node; descendant action
  keystrokes never bubble into row activation. Child gesture recognizers win
  their own taps. Disabling a row does not disable its independent actions.
- No selection, loading/error state or Form value is invented. Native FormField
  descendants retain validation/save/reset and state through reflow.
  Borrowed focus nodes are never disposed. There are no timers or overlays in
  the generic owner; implicit color animation honors reduced motion.
- `semanticLabel` adds a row announcement. Callers replacing the whole label
  exclude only passive content semantics, preserving action semantics.
  Groups/items have native list/listItem roles; passive Items have no button role.

## Styleguide and dependencies

Thirteen actual-component examples cover Basic, Variant, Size, Icon, Avatar,
Image, Group/Separator, Header, Link, Dropdown, RTL, all-parts Composition and
States with independent secondary actions. All callbacks use local state.

Separator, Avatar and Button are merged dependencies. Actions now use final
Button outline/small styling and the Avatar/Group examples use final accessible
round outline/ghost icon-only buttons. The composition example uses final Badge
for the member role. The fixture uses final controlled Checkboxes; the Form-state
regression composes final DInput. No temporary radio choice exists to replace.
The Dropdown example uses accepted `DDropdownMenu`, trigger, content, group and
ordinary item primitives with passive xs Items and explicit padding. Its menu
owns focus, selection, dismissal and trigger focus restoration; Item remains the
compact content-row owner. No unmerged dependency is imported. The styleguide is
implemented after independent reference/native acceptance.

## Application adoption and audit

Implemented:

- `TagsPage` keeps its ShellSelector, request identity, refresh/error handling and
  ListView.separated lazy builder. Only the ready row is now `TagDirectoryRow`
  using DItem outline/link, icon, title/description and a trailing count column.
  `openTag`, tag slug, PM/topic pluralization and keys remain app-owned.
  The public presentation row allows the native fixture to mount production UI.
- `AssignmentDetailRow` replaces its Material/ListTile surface with muted Item,
  existing authenticated avatar adapter, title, full untruncated identity/status/
  note and edit indicator. The caller still supplies the permission-gated edit
  callback; no controller, mutation, picker, busy guard or persistence changed.
  The existing full accessible label is retained without duplicate passive text.

Audited retained alternatives / adjacent ownership:

- TopicListRow, TopicInboxRow, NotificationRow and aggregate topic adapters have
  bespoke timeline/read-state/column and per-row selector ownership. Their
  keyboard selection and compact metadata layouts are not Item's content-row
  contract. Retained rather than changing these to an eager ItemGroup.
- Draft rows retain their resumable/deleting/remote-fallback interaction and
  custom 520px content breakpoint; invite and user activity/summary rows retain
  their table/reading layouts. A later adapter-specific review can compose
  passive parts without replacing their state owners.
- Assignment editor suggestion rows are picker choices (Select/Combobox), not
  Item selection controls. They remain unchanged. Checkbox/Radio/Switch tiles
  belong to their field owners, per the reference's Item-vs-Field distinction.
- Core user-menu, anchored picker, choice/command menus, bookmark option sheets,
  and plugin timezone/audio-device choice rows retain their menu/selection owner.
- Events participant records and event-day ListTiles are additional plausible
  content-row migrations. They remain **candidate follow-ups**, pending adjacent
  Calendar/Dialog/Events fixture ownership. Their search/request authority and
  day-dialog stale-source checks must survive an eventual migration.
- Voice chat's CookedHtml ListTiles belong to the Message/Bubble/timeline work;
  reaction identity rows retain UserCardTarget hit/focus ownership and compact
  24px avatar presentation. No media/network owner moves into Item.
- Page-scale empty states and inline error banners in tags/aggregate/group/Events
  remain for Empty and Alert. Those owners may edit adjacent regions in the same
  files; coordinator should reconcile only the ready-row diff.

## Verification and review queue

Focused tests cover source geometry and image sizing, RTL placement, alpha and
live radius, group spacing/semantics, disabled row with live secondary action,
Return/Space/tap isolation, borrowed focus lifecycle, Form value retention through
reflow, exterior-only focus pixel painting, all examples at regular and 200% RTL,
temporary menu selection/dismissal, production fixture callbacks and existing
TagsPage/AssignmentSheet behavior. The styleguide shell regression suite also runs.

Native fixture entrypoint: `lib/item_review_main.dart`. It starts with the actual
TagDirectoryRow and AssignmentDetailRow production widgets, using local records,
including multi-line notes, user/group assignees and permission changes. It links
to the real full styleguide and supplies theme, RTL and text-scale controls.
The independent reviewer exercised tag navigation, assignment editing and the
permission-disabled text state. In dark mode with RTL and 200% text, the initial
bundle exposed ellipsized assignment notes despite relaxed line limits. Commit
`fcc26238982fb062a84b4f964995d7026e547af7` makes unclamped title/description
overflow clip while preserving ellipsis for explicit clamps. The rebuilt
exact-source fixture then showed every line of both real assignment notes and
retained their edit actions.

The corrected focused run passed 35 Item/styleguide/migration tests with seed
9092026. Root and full-profile `flutter analyze --no-pub`, formatting and
`git diff --check` pass. Build provenance is recorded in `item-build.md` and
`reference/item/review-build.json`. No VoiceOver, iOS/Linux device,
authenticated screen or pixel-parity claim is made.

## Pinned-main integration preparation

This bounded follow-up keeps the generic Item owner unchanged. Tags ready-row
presentation and assignment detail presentation retain the current-main request,
lazy list, permission and accessible-label boundaries. Final Button activation
passes the existing independent row/secondary-action checks; the added composed
Checkbox regression checks pointer and Space isolation. The final Input retains
Form save/reset and edits through large-text RTL reflow.

The earlier source-owner limitation above is historical. The independent review
subsequently completed browser/native inspection through the repository's
serialized desktop lease, without an admin-policy retry or workaround. The
accepted Dropdown composition passed its focused selection, semantics,
dismissal and trigger-focus-restoration regression in the final candidate.
