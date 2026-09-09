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
`codex/review-data-table-merge`. The implementation history is preserved from
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

Follow-up candidate `1f6e1cc9bbecf8b653e912565953e8df3a95a46f` starts from
main `5e79d2dd99c734df9a3e30e3e7f86a1a42853a1c` and preserves every other
component's progress and workflow. Its 34 Data Table/example/styleguide-shell
checks passed with seed `9092026`; root and full-profile analysis remained
clean. Data Table's component, example bodies and fixture are unchanged from
the final native bundle. Main's newer Field layout change is not instantiated
by these Data Table examples; their composed control implementations are
unchanged.

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

Reviewer follow-up `0f50f53e` also removes the visible Actions heading from the
48px icon column, matching the official empty header and avoiding clipped text.
The column retains its semantic label. The existing action regression now checks
that the heading is absent before opening the menu and present inside it.

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

The page-size correction's isolated bundle is
`/private/tmp/data-table-review-4f70.9Joknh/Data Table Review 4f70.app`, identifier
`org.discourse.native.datatable.4f70`. Its kernel matches the original build:
`67fa17530f6572f94536b8f92a7e5b9de376e2f82dc6058b12d093cf870cc307`.
Deep strict signature verification passed. Only the copied bundle's name,
identifier, URL registration and ad-hoc signing metadata changed; repository
runner, provisioning, release settings, pubspecs and lockfiles were untouched.

The final action-heading correction is built from
`0f50f53e2fc1539415c61f2bbf4a0f1ca36b2dbd` at
`/private/tmp/data-table-review-0f50.jYpaUM/Data Table Review 0f50.app`, identifier
`org.discourse.native.datatable.0f50`. Original and copied kernels both hash to
`172da87b7d27513776ea9236ede53641569191faaef784ac4b42528aab0558e6`;
deep strict signing verification passed. All 18 Data Table/example tests passed
with seed `9092026`, root analysis was clean, and the macOS rebuild succeeded.

The initial bundle was
`/private/tmp/data-table-review-3191.Xaw99t/Data Table Review 3191.app`, identifier
`org.discourse.native.datatable.3191`, kernel
`c27c5234d8c29d43445523b3b711b5ce817457330ae299f36df6809caf9d4fca`.

At that stage, acceptance was pending the corrected footer's native check and the
rendered reusable Tasks controls comparison. On 2026-09-09 at 17:53 UTC the
reviewer acquired desktop access, but approved CUA `getApp` repeatedly returned
`-10005: timeoutReached` for the final bundle's exact path and identifier,
including after a CUA session reset. `getState` reported that isolated app as
running; no app binding or accessibility state was returned, so its UI could
not be inspected or closed through the approved surface. The desktop lease was
released promptly. No alternative UI automation or security changes were used,
and no final acceptance or merge is claimed. The subsequent leased Button Group
reviewer confirmed normal native-control recovery, selected the exact Data
Table bundle identifier and quit its old instance through the native menu. This
is cleanup/control evidence only, not a Data Table visual pass. The reviewer
has rejoined desktop FIFO for a fresh launch and the remaining checks.
No iOS/Linux device or spoken
VoiceOver pass is claimed. All examples use local immutable fixture data.

### Accepted menu follow-up integration

Candidate `228f838c8b476850f15029b37c9856b9f1da789e` starts from main
`d647400602824226d70d1328fba2a141195dc559`, preserving all other progress
rows and workflow. It incorporates accepted Dropdown Menu follow-up merge
`85f9265bf2593a7edc0693582b7eadf1c6645b8d`: stable live item ordering,
popup-local focus scrolling, removal of redundant Popover autofocus and the
RTL chevron correction. The original Data Table fixes are unchanged.

All 91 Data Table/example/Dropdown Menu/Select/Popover/styleguide-shell tests
passed with seed `9092026`. Root/full analysis and the macOS build passed.
The new final fixture is
`/private/tmp/data-table-review-228f.B2Ba4K/Data Table Review 228f.app`, identifier
`org.discourse.native.datatable.228f`. Original and copied kernel hashes match
`cfe9534d81da826c7ec00558ab73bfe82bfd743ac99518948dbbae11447cb4dc`;
deep strict signature verification passed. The same isolated name/identifier,
URL-registration removal and minimal ad-hoc entitlement procedure was used.
No repository runner, provisioning, release settings or lockfiles changed.

The reviewer withdrew from desktop FIFO during integration/rebuild and rejoined
with the completed bundle. Remaining native checks include the footer and empty
action heading plus menu activation, repeated column toggles and restored focus
against the updated parent. The rendered Tasks comparison remains pending.

At 18:34 UTC on 2026-09-09, the reviewer acquired its desktop lease and made
one fresh-session CUA call for the exact `228f` bundle. The approved surface
reported that the Mac is locked and requires manual unlocking. The lease was
released immediately; no alternate route or unlock attempt was used. The
rebuilt fixture has not received its final native pass and remains unaccepted.

### Final acceptance — 2026-09-09

After user-confirmed unlock and normal-CUA recovery, the reviewer acquired its
own desktop lease at 19:03 UTC. The exact `228f838c` fixture rendered normally.
Actual native verification confirmed the empty visual Actions header with its
semantic label retained; repeated Amount off/on toggles; row-menu Down/Return
activation with `Opened m5gr84i9`; visible restored trigger focus and keyboard
Return/Escape reopening/dismissal. No ancestor-scroll jump occurred in these
menu interactions against the accepted Dropdown Menu follow-up.

At 360px and 200% text with reduced motion, selected page sizes 10 and 20 are
fully readable in Light LTR and Plum RTL. Actual page-size changes update the
page count between 1 of 2 and 1 of 1; the footer wraps without overflow. Earlier
exact-source coverage remains valid for unchanged documented compositions,
selection, sorting, filtering, dynamic rows and the other live palettes.

The rendered official `https://ui.shadcn.com/examples/tasks` reference was
compared for the reusable Asc/Desc/Hide header menu, View column toggles and
advanced footer. Actual interactions applied ascending sort, hid/restored
Priority, changed page size 25 to 10 and exercised next, previous, last and first
with corresponding page counts. Its supporting Radix Tasks View menu closes
after a toggle; the primary Base UI payment example and this port retain the
previously verified repeated-toggle behavior. The Tasks domain app itself is
not a required production migration.

Both review surfaces were closed and desktop access released. All outstanding
native/reference checks are complete, and the styleguide entry is accepted as
implemented. No iOS/Linux device or spoken VoiceOver pass is claimed. Final
main integration preserves the inspected Data Table bodies; newer Popover
transition parameters retain the same defaults, and these examples do not use
its explicit anchor lifecycle. Affected composition checks are rerun on the
final integration rather than repeating unchanged native work.
