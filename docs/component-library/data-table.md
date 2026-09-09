# Data Table reference and acceptance

Reference date: 2026-09-09. The frozen official Markdown at
`https://ui.shadcn.com/docs/components/base/data-table.md` hashes to
`31d46187a08d79ce41dd8991599ce86ff2d6fba0b99ae4ebff84cfbccce6cff4`,
exactly matching `catalogue.json`.

The linked official Tasks sources were read at shadcn-ui/ui commit
`3ba91b1cc83e1bbe4ab35a422ff2a694849c5048`:

| Source | SHA256 |
| --- | --- |
| `data-table.tsx` | `916d3e0263c24138e84712e2deb94853bb6882d702312082979ab3273a0eb682` |
| `data-table-column-header.tsx` | `d4080a3bae2c83f83e8439e8f10b4e5436afde749f9fc7e9e287d91f230b805f` |
| `data-table-pagination.tsx` | `61dab49419a93660f4e6ed30272b083c1e21116a627a92f6125856fa625769bd` |
| `data-table-view-options.tsx` | `862c1cc187d56078bfd68f55e7d61862654bea8aeac4b3f0d740ec6dba123e08` |
| `data-table-row-actions.tsx` | `d301603722e780b222d90ad3170d7d7d12ed613c35e53f03ce8bea21ddcff7ee` |
| `data-table-toolbar.tsx` | `dca08595446c868527e93aa8649e56910329e4302c71bdc4f7be4ade8509f388` |

The primitive Table registry was also verified at
`https://ui.shadcn.com/r/styles/base-nova/table.json`, SHA256
`054c89df40058a96723c9ed8cde6308e738f3a303fd19301ce94ade032306b60`.
There is intentionally no `base-nova/data-table.json`: the documentation is a
headless composition guide, not another registry renderer.

## Source-to-Flutter mapping

- TanStack `ColumnDef<T>` becomes immutable `DDataTableColumn<T>` with stable
  string ID, typed cell/header builders, an optional comparator and filter.
  Flutter owns no JavaScript or TanStack runtime.
- TanStack state becomes `DDataTableState`: one-based page/page size, optional
  sort, per-column text filters, hidden column IDs and selected stable row IDs.
  It can be local, borrowed through `DDataTableController`, or controlled with
  `state`/`onStateChanged`.
- Local mode applies filter, stable sort and pagination to the complete input.
  Manual mode displays the caller-prepared page and reports requested state;
  networking, loading, errors, caching and query cancellation stay in adapters.
- The table wrapper is a one-pixel `border` token with `rounded-md` (`0.8 ×`
  the live host radius) and clipped horizontal overflow. `DTable` preserves
  14/20 text, 40px header minimum, row reading order and semantic table/row/
  column-header/cell roles. The no-results row is 96px high.
- Selection uses the completed 16px Checkbox owner inside its 40×32 desktop or
  48×48 touch target. The header selects only selectable rows on the current
  page and exposes mixed state. Selection follows row IDs across sort/filter/
  page/reorder changes rather than visible indices.
- `DDataTableColumnHeader` reproduces the 28px ghost sortable trigger and
  Asc/Desc/Hide menu. `DDataTableColumnToggle` reproduces the end-aligned 176px
  Columns menu whose checkbox items stay open for repeated changes.
- `DDataTableFilterField` keeps the documented 384px maximum and completed
  Input editing/IME/Form semantics. Row actions remain caller-authored
  Dropdown Menu cells, so opening or activating one never turns the row into a
  competing control.
- `DDataTableSelectionSummary` uses 14/20 muted text. The advanced
  `DDataTablePagination` composes the prepared real Pagination and Select owners:
  a 70px page-size Select, 100px page count, 32px outline first/previous/next/
  last controls and responsive wrapping. No temporary renderer is shipped.
- All padding and alignment are directional. DTable provides natural-width
  horizontal scrolling at narrow widths and enlarged intrinsic row heights at
  200% text. Colors, fonts, radii and reduced-motion behavior resolve live from
  the host theme and the composed component owners.

## Adoption audit

The core Users directory is the only large structured dataset that superficially
resembles this guide. It deliberately remains its specialized renderer: it has a
pinned identity pane, synchronized virtualized vertical viewports, persisted
resizable metric columns, server-side infinite loading, per-metric bars and an
administrative column-order editor. Replacing it with the eager Data Table would
remove capabilities and regress large-directory performance.

Alert Tables remain on `DTable`: their nested alert groups, quotations,
expand/collapse state and links are passive document structure rather than a
homogeneous sortable/filterable row model. Topic, Chat, SuperList and badges
surfaces are card/timeline/infinite feeds and are not converted gratuitously.
No plugin currently owns a bounded homogeneous grid suitable for migration.
The searchable styleguide therefore supplies the first real Data Table adoption
with self-contained immutable payments.

## Remaining review gate

The implementation branch may use prepared Dropdown Menu source
`codex/review-dropdown-menu-candidate@d273c27e788bb3991c773c7432e0b8c927715651`
for isolated work only. Dropdown Menu still requires its own acceptance and main
merge. Pagination is pinned from task
`01a08606-c9d5-7741-bfe0-e4ff531ff9b7` at
`codex/ui-pagination@cd69ff21400192e6a141a675ffb7ec6a7199526c` after 10
focused and 71 combined dependency/styleguide tests plus clean root/full
analysis. It includes prepared Select/Field ancestry. Require accepted
Pagination, Select, Field and Dropdown Menu revisions from current main before
Data Table can merge.

The independent Data Table reviewer must compare the exact official rendered
payment table and reusable Tasks controls against an exact-source macOS fixture
in light/dark/custom palettes, 360px, 200% text and RTL. It must exercise actual
filter input, sort Asc/Desc, repeated visibility toggles, page size/page buttons,
mixed/all/none selection, row menu keyboard focus/restoration and dynamic data.
Do not claim iOS/Linux or spoken VoiceOver without actual checks.
