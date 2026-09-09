# Tabs reference and acceptance

Frozen catalogue date: **2026-09-08**.

## Sources

- Frozen documentation: <https://ui.shadcn.com/docs/components/base/tabs.md>,
  SHA-256 `38d09f015f5856ced34f5af2449439611c845e952472c2382f2123d6fef2af0a`.
- Rendered documentation: <https://ui.shadcn.com/docs/components/base/tabs>.
- `base-nova` registry item:
  <https://ui.shadcn.com/r/styles/base-nova/tabs.json>, inspected
  2026-09-09, SHA-256
  `b4552a0329dd9a6e2bfaf03405c133874df5a4930c7bb3dd84c9ab5c45b89402`.
- Base UI behavior/API reference:
  <https://base-ui.com/react/components/tabs.md>, inspected 2026-09-09,
  SHA-256
  `c45845004593acab3c87dd79246f9591035fcbb0de16fdd990105c47a2d804aa`.

The frozen documentation hash was reproduced byte-for-byte before
implementation. Its covered sections are Usage, Composition, Line, Vertical,
Disabled, Icons, RTL, and API Reference.

## Source-to-Flutter mapping

| base-nova source | Flutter mapping |
| --- | --- |
| Root `flex gap-2`, horizontal roots become columns | `DTabs` uses an 8 logical-pixel gap, a column for horizontal tabs and a row for vertical tabs. At widths below 320px or text above 150%, vertical content stacks below its still-vertical list so neither side overflows. |
| List `w-fit`, `rounded-lg`, `p-[3px]`, horizontal `h-8`; default `bg-muted`; line `gap-1 bg-transparent rounded-none` | Intrinsic list, host `radius` (lg), 3px inset, 32px pointer height, muted default surface, transparent square line surface and 4px trigger gaps. A horizontal `SingleChildScrollView` keeps long/dynamic lists usable at narrow widths. |
| Trigger `h-[calc(100%-1px)]`, `px-1.5 py-0.5`, `rounded-md`, `text-sm/medium`, `gap-1.5` | 25px pointer trigger, 6px horizontal/1.5px vertical inset, `radius × .8`, 14/20 host-font medium text, inherited 16px icon theme and caller-composed 6px icon gap. Touch platforms retain at least 48px list interaction height around compact artwork. |
| Inactive `foreground/60`; hover/active foreground; disabled 50%; light active background; dark input/30 plus input border; active shadow-sm | Live `DTokens` foreground opacity, hover/selection, disabled opacity, background/input semantic mapping and small 1px-y shadow. No cached palette values. |
| Focus border plus 1px ring and 3px `ring/50` | Outside-only custom-painted 1px focus outline and 3px half-alpha host focus ring, avoiding interior tint. |
| Line active pseudo-element: horizontal bottom -5px, 2px high; vertical right -4px, 2px wide | A 2px foreground rule paints 4px beyond the trigger. Vertical placement uses logical end, including RTL. |
| Root value/defaultValue/onValueChange, List activateOnFocus/loopFocus, disabled fallback and missing fallback | Local `DTabs`, `DTabs.controlled`, borrowed `DTabController`, `DTabChangeReason`, manual/automatic activation, wrapping/non-wrapping roving focus, and dynamic disabled/missing reconciliation. Controlled values are never rewritten. |
| Arrow/Home/End navigation with disabled items skipped | Orientation-aware arrows, RTL horizontal direction, Home/End boundaries, Enter/Space manual activation, focus reveal in horizontal overflow. |
| Panel hidden by default; `keepMounted` opt-in | `DTabPanel` unmounts hidden child state by default. `maintainState` keeps it offstage with ticking and semantics disabled. Focus in a panel hidden by external selection returns to its matching trigger. |

## Acceptance criteria

- Public generic `DTabs<T>`, `DTabList<T>`, `DTabTrigger<T>`,
  `DTabPanel<T>`, `DTabController<T>`, variants and change reasons are exported
  from `package:discourse_native/discourse_ui.dart` without app dependencies.
- Every frozen example has an interactive styleguide entry using the final
  component, including the exact four-panel Card composition.
- Selection works in local, controlled and borrowed-controller forms. Dynamic
  reorder/removal/disable skips unavailable items and reports fallback reason.
- Pointer, semantic tap, Tab entry, arrow/Home/End roving focus, manual
  Enter/Space activation, automatic activation, disabled skipping and RTL are
  covered. Borrowed focus/scroll/selection resources are not disposed.
- Hidden panel lifecycle is explicit, retained panels do not tick or expose
  semantics, and focus does not disappear into a removed panel.
- Default/line geometry, live light/dark/custom tokens, host font/radius,
  reduced motion, 200% text, 260px layout and touch targets are covered.
- Group, Chat channel-info and Diagnostics top-level tabs use the generic
  renderer without moving routing, plugin, permission or data ownership.

## Adoption audit

Migrated:

- `lib/src/shell/group_page.dart`: core and plugin primary tabs. The adapter
  retains capability filtering and translates selected generic values back to
  `GroupRoute`.
- `lib/src/plugins/chat/chat_channel_info_view.dart`: Settings/Members line
  tabs. The adapter retains channel/category labels and `ChatShellService`
  routing; the enclosing app bar remains 58px while the shared trigger keeps
  the measured 25px base-nova artwork.
- `lib/src/shell/diagnostics_panel.dart`: General, Topic scroll and dynamic
  plugin tabs. Capture/plugin state and callbacks remain diagnostics-owned.

Retained alternatives:

- `forum_tabs_bar.dart` and `aggregate_view.dart` are browser/workspace tabs,
  with close, reopen, reorder, persistence, drag feedback and context menus.
  They are not layered content tabs and remain application-owned.
- `topic_list_navigation.dart` combines feed selection with unread badges,
  filters, period selection and responsive toolbar layout. `user_menu.dart`
  similarly owns notification types, unread state and a vertical app rail.
  Those domain strips retain their renderer until a dedicated adapter can
  preserve all of those contracts rather than forcing them into generic Tabs.
- Group secondary navigation and Preferences use sidebar/picker navigation,
  not the frozen Tabs composition.

## Prepared review surfaces

The ordinary styleguide target (`lib/styleguide_main.dart`) contains all seven
frozen example groups with local sample data. Existing focused test harnesses
mount the actual migrated Group, Chat and Diagnostics widgets with local/fake
data; no account or network mutation is required. The implementation task did
not acquire the shared desktop lease and therefore makes no browser/native
render claim. The independent reviewer owns official rendered comparison,
macOS inspection, any resulting fixes, final reconciliation, and merge.
