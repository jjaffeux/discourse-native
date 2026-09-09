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
  `DDataTablePagination` composes the accepted Pagination and Select owners:
  a 70px minimum page-size Select, 100px page count, 32px outline
  first/previous/next/last controls and responsive wrapping. The Select grows
  to fit the widest scaled page-size value plus its border, padding and icon.
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

## Independent review

Reviewer task `01a0863a-ff5a-7fe1-bc5c-5f0809bfd69a` owns
`codex/review-data-table-final`. The implementation history is preserved from
`codex/ui-data-table`; see `data-table-review-handoff.md` for the source handoff.

All prepared-parent gates are satisfied by accepted local-main merges:

| Parent | Accepted merge |
| --- | --- |
| Pagination | `20f1673402d8b52370efacb5ca61d5f099810582` |
| Select | `57bbeb94368649a4665483180e4f5c84b5f33856` |
| Field | `5cd7f3694498e4e09e3c114639baca834b56705e` |
| Dropdown Menu | `5c6ab6a15d69c7241ab7d9345eb9f6d6418e2787` |

Candidate `4f702a45f0f9ab993a7cbced2406dc8d416a1c96` starts from main
`9834f36a9c4c44f1792e9970bf0a9abfcbedd47d`. Its changes are confined to
Data Table source, examples, tests, fixture, public registration and evidence;
the accepted parent implementations are unchanged. Date Picker import/export
conflicts were resolved by retaining both components.

### Completed rendered and native checks

The official rendered Base UI Data Table payment example was inspected through
the approved browser surface on 2026-09-09. Actual interactions covered Email
ascending/descending sorting, filtering to Carmella, repeated Amount visibility
changes, filtered-row selection and the payment action menu. The native fixture
was compared for control hierarchy, typography, alignment, borders, row states
and menu behavior; browser/native font rasterization is not pixel-identical.

The exact-source macOS fixture at `31912939` was inspected in Light, Dark,
Forest and Plum. Actual native interactions covered:

- Filter entry and clearing; Email ascending and descending row order.
- Repeated Amount column toggles with the menu staying open.
- None, mixed and all-current-page selection, with matching selected counts.
- Next, previous, last and first page actions; page size 10 to 20, exposing all
  12 payments and updating the page count.
- Reverse, remove-first and reset of dynamic rows while Abe's selection stayed
  attached to its stable ID.
- Row-menu Down/Return activation, the `Opened m5gr84i9` result, visible restored
  trigger focus and Return/Escape reopening/dismissal.
- Arabic RTL content and mirrored controls; combined 360px, 200% text, RTL and
  reduced-motion layout, including wrapped toolbar and pagination.

The large-text native pass exposed an unreadable selected page-size value in
the fixed 70px trigger. Reviewer fix `58aa1c03` measures the widest option using
the active font and text scaler. New LTR/RTL tests first reproduced truncation,
then passed for both the ordinary value and a selected custom value of 1000.
The earlier pass remains valid for unchanged table and action behavior.

The inspection session briefly produced a partially blank capture after a
sequence containing an unsupported key name. Reopening only the isolated
fixture restored rendering; the keyboard interaction was repeated successfully
with supported Down/Return/Escape input. This is not evidence of a diagnosed
component crash.

### Automated verification and exact-source rebuild

On candidate `4f702a45`, 74 focused Data Table/example/Pagination/Select/Dropdown
Menu/Table checks passed with seed `9092026`. Root and `profiles/full`
`flutter analyze --no-pub` passed without diagnostics. The fixture built with
`flutter build macos --debug --no-pub -t tool/data_table_review.dart`.

The corrected isolated bundle is
`/private/tmp/data-table-review-4f70.9Joknh/Data Table Review 4f70.app`, identifier
`org.discourse.native.datatable.4f70`. Its kernel matches the original build:
`67fa17530f6572f94536b8f92a7e5b9de376e2f82dc6058b12d093cf870cc307`.
Deep strict signature verification passed. Only the copied bundle's name,
identifier, URL registration and ad-hoc signing metadata changed; repository
runner, provisioning, release settings, pubspecs and lockfiles were untouched.

The initial bundle was
`/private/tmp/data-table-review-3191.Xaw99t/Data Table Review 3191.app`, identifier
`org.discourse.native.datatable.3191`, kernel
`c27c5234d8c29d43445523b3b711b5ce817457330ae299f36df6809caf9d4fca`.

Final acceptance is pending the corrected footer's brief native check and the
rendered reusable Tasks controls comparison. No iOS/Linux device or spoken
VoiceOver pass is claimed. All examples use local immutable fixture data.
