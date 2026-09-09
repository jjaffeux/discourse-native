# Table implementation and review queue

Status: **in_progress — native/reference rendered comparison pending**. Task
`01a0844a-0669-7780-92e8-33cc4314f64a`, branch `codex/ui-table`, isolated checkout
`/Users/joffreyjaffeux/.codex/worktrees/7328/discourse-native`.

## Frozen source

Retrieved 2026-09-09 from primary sources; the checked-in bytes are in
`reference/table/`:

| Source | SHA256 |
| --- | --- |
| https://ui.shadcn.com/docs/components/base/table.md | `16bcb89807973003dfc36d98bffe6a83ac3183e95cc9cb017809127c12fadb1d` |
| https://ui.shadcn.com/r/styles/base-nova/table.json | `054c89df40058a96723c9ed8cde6308e738f3a303fd19301ce94ade032306b60` |

The Markdown exactly matches the frozen catalogue and contains full default,
Footer, Actions and Arabic/Hebrew RTL example source. The registry contains the
base-nova owner. Separate `table-demo`, `table-footer`, `table-actions` and
`table-rtl` registry endpoints returned 404; their full examples are preserved
in the matching Markdown, not reconstructed from names.

## Source-measured mapping (16px root, logical px at 100%)

| Reference CSS | Flutter |
| --- | --- |
| `w-full overflow-x-auto`, natural no-wrap content | LayoutBuilder minimum viewport width, shared intrinsic columns, horizontal SingleChildScrollView |
| `text-sm` | DiscourseTypography.sm 14px / explicit 20px leading, normal weight, zero tracking; host font family |
| head `h-10 px-2 font-medium text-foreground` | 40px minimum cell, directional 8px horizontal padding, weight 500, live foreground |
| cell `p-2 align-middle whitespace-nowrap` | 8px padding, centered vertically, no-wrap inherited text; caller may explicitly wrap sized authored content |
| invoice `w-[100px]`, first cell `font-medium` | MaxColumnWidth(FixedColumnWidth(100), IntrinsicColumnWidth), weight 500; text scaling can increase natural minimum |
| amount `text-right`, RTL plugin mapping | AlignmentDirectional.centerEnd; column zero moves to the reading start |
| row/section `border-b`, last body row border zero | 1px token border rules; no last body rule; footer top rule |
| footer `bg-muted/50 font-medium` | live muted alpha multiplied by .5, weight 500, spanning three-column Total |
| hover / `has-aria-expanded` | half-muted background, 150ms ease-in-out color transition; zero duration with disableAnimations |
| `data-state=selected bg-muted` | caller-controlled selected state, full muted color and selected semantics |
| caption `mt-4 text-sm text-muted-foreground` | bottom caption, 16px gap, 14/20 typography and live mutedForeground; width follows entire scrolled table |
| checkbox end inset override | explicit directional cell padding; checkbox/Form remains a composed caller widget |

No table border radius, shadow or icon artwork is present in the reference.
Host radius is therefore unused, not replaced by an arbitrary shape. Product
menus use existing StyleguideAction/Material MoreHorizontal icon and native
MenuAnchor as the coordinator-authorized temporary Button/Dropdown Menu
composition. These parts are not claimed as completed catalogue components.
The source's excerpt total remains $2,500.00 even for three rows.

Widget tests measure 40px header **cell** bounds, 36px default body cell bounds,
100px minimum invoice column, aligned amount edges, a spanning footer and the
16px caption gap. Rules occupy separate logical pixels between cells. Actual
browser collapsed-border edge alignment, typography rasterization and the
native rendering remain explicit review gates; these are source/layout
measurements, not rendered parity claims.

## API and native adaptations

DTableHeader/Body/Footer/Row are typed immutable composition values, analogous
to Flutter TableRow. DTableHead/Cell/Caption are widgets. The single rendering
owner supports column spans because stock Flutter Table does not. It uses
Flutter TableColumnWidth policies; fixed/flex columns avoid intrinsic queries
on rich authored HTML, while ordinary columns retain natural no-wrap width.
Explicitly fixed columns should use softWrap for content that can outgrow them.
No row spans are exposed; no frozen composition requires them.

The eager layout is intended for bounded presentation tables. It does not
create sorting, pagination, selection logic, data loading or network ownership.
Selected/expanded values come from callers; menus, buttons and fields keep
native Actions/Focus/Form/controller behavior. There is no extra passive-row
Tab stop. A provided ScrollController is borrowed; scrollable-owned resources
follow Flutter lifecycle. Child keys are scoped to their row identity.

Semantics use a table node containing row nodes and column-header/cell nodes,
with reading-order sort keys and explicit selected flags. Caption is a sibling
of the semantic table, so it cannot violate Flutter's table-row hierarchy.
Semantic row rectangles and cells use the same table coordinate space.
Large text increases cell heights; natural columns scroll horizontally rather
than truncate. Directional alignment mirrors in RTL. Touch targets and visible
focus remain with composed interactive controls; the passive table adds none.
No FormField is introduced for a passive presentation container.

## Adoption audit

- **Migrated plugin:** Prometheus `AlertTables` uses DTable for its actual
  tabular presentation. Plugin-owned group collapse, data/status order,
  permission-dependent quote callback, matching link timestamps, Local Dates,
  selectable text, 2:3 name/description flex sizing, scaled date width, compact
  padding and borrowed scrollbar controller remain. Loading/error state is
  owned by the surrounding topic; AlertTables itself takes ready data and can
  have zero groups. No fabricated generic loading/error props were added.
- **Migrated downstream example:** Skeleton's five-row ready content uses
  DTable while its authored compact spacing and loading placeholders remain.
- **Retained core Users grid:** `users_page.dart` uses two lazy vertical lists,
  pinned identity columns, synchronized vertical positions, a horizontally
  scrolling metric viewport, persisted column widths, isolated hover notifiers,
  sorting/filtering/pagination, and snapshot-derived maxima. Replacing those
  lists with this eager table would remove its virtualization/scroll contract.
  This is a specific Data Table/application-grid review boundary. No Users code
  changed; Chart's metric marks and Resizable's width adapters remain owned by
  their separate unmerged tasks.
- **Retained cooked HTML:** `CookedHtml` delegates authored table markup to
  HtmlWidget and its CSS/span/selection rendering. Replacing DOM rendering with
  presentation models would change authored content, unlike the migrated
  serializer-based Prometheus tables. No cooked parser changed.
- **Retained Typography article tables:** the frozen Typography examples have
  16/24 prose, full cell borders, alternating rows, 16px horizontal padding and
  authored mixed alignment. They intentionally demonstrate that separate
  Typography reference, whose design differs from base-nova Table.
- **Retained core topic list/group/member rows:** responsive discovery list
  compositions are not HTML-style tables. Their navigation, avatars, hidden
  small-window metadata and list semantics remain with their existing owners.
- **Poll:** ranked/vote results are bars and result lists, not tabular owners;
  Chart owns their rendering work. No Poll edits.

No generic component imports shell, model, networking or plugin modules.
No dependency, Flutter pin or lockfile changes.

## Verification and native handoff

See the Table progress row for final commands and build provenance. The local
review entrypoint `tool/table_review.dart` mounts the actual production
AlertTables and opens the actual ComponentStyleguidePage. It supplies local
ready/empty data, refresh, quote-permission toggles and callback feedback,
light/dark, RTL and 200% text. It also installs the real Local Dates plugin and
uses the native timezone environment. No credentials, stores or data mutations
are needed. Link buttons point only to example.com fixture URLs.

Native checklist after coordinator grants a desktop slot: compare official
base-nova invoices/footer/actions/RTL at matched width and text scale; inspect
light/dark and custom palette; test keyboard Tab/Return/Escape and visible focus,
menu restoration, hover/selected/open state; inspect AlertTables at narrow and
wide widths, text scaling/RTL, Local Dates, quote permission, collapse through
refresh and empty→ready. Validate mouse/trackpad horizontal scrolling and
keyboard access. No browser/native slot, VoiceOver, iOS/Linux device inspection
or pixel-parity claim has been made during independent implementation.


## Prepared build evidence

- Source commit: `f98c86e983088205647b11c97c6027ce706ad8dd`.
- Build: `flutter build macos --debug --no-pub -t tool/table_review.dart`.
- Copied bundle: `/tmp/table-review-7328/Table Review 7328.app`.
- Verified final ID: `org.discourse.tablereview7328`; URL scheme:
  `discourse-table-review-7328`; display name: `Table Review 7328`.
- Xcode's debug settings overrode the temporary xcconfig bundle ID. The copied
  bundle's Info.plist was corrected, then the entire copy was ad-hoc signed and
  `codesign --verify --deep --strict --verbose=2` passed. The copied kernel
  remained byte-identical to the original build kernel after this correction.
- Kernel SHA256:
  `8f46827b04e593cd6fa1f05daea14e315b1a00c42a60f4cf5291ea4b622a6e79`.
- Every tracked `lib/` source, fixture entrypoint, root lock and Flutter pin was
  hashed before and after building and matched. Temporary runner changes were
  restored. Subsequent handoff commit changes documentation only.
- Logs, source hashes and signature output:
  `/tmp/table-review-7328/build.log`, `provenance.json`, `signature.log`.
- No build touched `/Users/joffreyjaffeux/Code/discourse-native/build`.
  The prepared app has not been launched. Status remains **awaiting_slot**.


## Pinned-main integration — superseding review artifact

Merged pinned main `e612ad7b47413fa890b35ae3b55a6f6d37b08cf7` into this component
branch. All non-Table progress rows match that main snapshot exactly. Table's
menu and selection examples now use merged DButton; only native MenuAnchor
remains pending Dropdown Menu. No further AlertTables/Skeleton adapter changes
were required; custom spans, semantics and the virtualized Users boundary remain.

Root/full locked resolution and analysis passed. The integration run passed 50
focused Table, AlertTables, Skeleton and styleguide tests with seed 9092026.
After selecting DButton's 32px regular visual surface for the menu trigger, all
seven DTable tests passed again.

The **current** bundle replaces the earlier artifact at the same isolated path:
`/tmp/table-review-7328/Table Review 7328.app`. Source commit:
`80c801e69ee94b8f1d02ca71ccb489bc53aec257`. Copied/built kernel SHA256:
`ec4e523c98e3978b530bf4adda8f52ce452864c006d8d9bb3d54f0c392c54e4a`.
Final ID `org.discourse.tablereview7328` and URL scheme
`discourse-table-review-7328` remain unique. Runner edits restored; tracked
source, fixture, pin and lock byte equality verified.

The copied app is ad-hoc signed with only `com.apple.security.cs.allow-jit`,
`com.apple.security.cs.allow-unsigned-executable-memory` and
`com.apple.security.cs.disable-library-validation`. Entitlement read-back
exactly equals this allowlist; no push or other restricted entitlement remains.
`codesign --verify --deep --strict --verbose=2` passed. Read-back is stored at
`/tmp/table-review-7328/entitlements-readback.plist`, alongside provenance and
signature logs. No browser/native app use; **awaiting_slot** remains in effect.
