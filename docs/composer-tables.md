# Composer tables

Use **Insert → Table** to insert a two-column table, or open a post/draft that
already contains a Markdown pipe table. Headings and body cells are editable in
place. The editor composes the same `DDataTable.softHeader` variant
as cooked posts, with Native inputs, menus and buttons.

- Column menus insert before/after, move earlier/later, and delete columns.
- Numbered row menus insert above/below, move up/down, and delete body rows.
- **Add row** and **Add column** append to the table. The header stays first,
  and deleting the last column is disabled.
- Tab/Shift+Tab move between cells; advancing past the last cell adds a row.
  Enter/Shift+Enter move within a column. Escape returns to prose.
- Native selection, clipboard and undo shortcuts act on the focused cell.
  Bold, italic and code shortcuts insert Markdown in that cell.
- Moving or clicking immediately before a block selects the whole component.
  The selection outline frames only the table, leaving its action buttons outside.
  Backspace or Delete removes it; Left/Up returns to preceding text and Right/Down moves
  after it. Enter opens the selected table's first cell. This boundary behavior
  is shared with details, quotes, images, galleries, polls and upload slots.
- Column resizing is local presentation state; column ordering changes the
  source. Wide tables scroll horizontally.

Every accepted change synchronously updates the composer's canonical Markdown,
so drafts and submission use the same source as other composer edits. Cell edits
replace only that cell's content. Missing trailing cells display as empty; editing
one adds the missing delimiters to that row. Merely opening a table leaves the
source unchanged, including any surplus body cells. Row moves retain authored
lines; column moves carry cell contents and alignment markers together. Column changes can add
boundary pipes to a table authored without them. Pasted pipes are escaped and
cell line breaks become `<br>`.

Recognition includes header-only and single-column pipe tables. Header and
delimiter widths must match; body rows may have fewer or more cells. Mismatched
headers, quoted/list tables, fenced or indented code, and HTML remain ordinary
source. Active main editor IME composition defers projection. Table edits reject stale source and
inactive/submitting composer sessions.

`ComposerInteractiveSyntaxProjection` preserves the table widget's identity
across its own edits and gives its nested controls pointer/keyboard ownership.
`ComposerEmbeddedEditor` keeps native cell text actions from resolving to the
surrounding composer, gives cells a separate focus scope, and groups
accessibility traversal outside the main text field. Its viewport transform
keeps cell input/accessibility coordinates aligned with the scrolled content.
Editable columns use the Native table's `onCellTap` and `onHeaderTap` callbacks
and text cursor to activate their input across the full cell, including padding.
`DTableCell` owns this hit area; nested inputs, action menus and resize handles
retain their own gestures and semantics. Submitting disables cell activation.

## Verification

`test/composer_tables_test.dart` covers source parsing and transformations.
`test/composer_table_test.dart` mounts the real composer and checks menus,
keyboard navigation, cell focus/composition, paste, undo/redo, source drift,
submission locking, accessibility traversal, and narrow layouts at 200% text
in light/dark themes.

The 31 table-specific tests and 301 accompanying composer, cooked-table and
Native control-adoption regressions pass. Coverage includes short body rows,
lossless edits, and clicking/selecting/typing in a table after scrolling a long
post. The supplied full-post reproduction also passes a local widget check.
Focused static analysis and the macOS debug build pass. Native review of the
supplied post confirmed both tables render and cells in each remain editable
after scrolling, without switching the table to Markdown.

For native review, run the in-memory fixture without a forum account:

```sh
flutter run -d macos -t tool/composer_table_review_main.dart
```

The fixture includes narrow/wide, light/dark and RTL controls, plus a link to the
component styleguide. It uses fake API and draft storage. To reproduce a longer
post locally, set `COMPOSER_TABLE_FIXTURE_BASE64` to its UTF-8 source encoded as
base64 through `--dart-define-from-file`; do not commit private fixture content.

### Full-cell hit area verification (2026-09-18)

The 55 focused composer-table, Native Table and Data Table widget tests pass,
including mouse clicks near header/body edges, empty cells, typing after focus,
column dragging and action menus in both themes. Full static analysis passes.
Native macOS verification used the production composer fixture: top-left and
bottom-right body padding and header padding accepted edits in the wide light
layout; body padding also accepted edits in the narrow dark layout. The Data
Table styleguide page was inspected. The new editable-cell example is covered
by static analysis; native column dragging was inconclusive, with resizing
verified by widget tests. No iOS or Android device verification was performed.
The installed Flutter SDK was 3.47.4; the repository pin was not changed.

### Table context actions (2026-09-18)

Secondary-clicking a composer body cell (including its padding or row-number
control) opens its row actions: insert above/below, move up/down, and delete.
Headers expose column actions. The Native context trigger can explicitly claim
secondary gestures from descendant editors; primary click, text selection,
keyboard editing and resizing keep their existing owners. Right-click does not
select the table's Markdown range. Block selections retain their outline when
focus moves into a menu. Submitting closes the menus and stale actions remain
inert.

Read-mode tables have a Copy table button beside Columns. It copies the complete
table as plain-text Markdown, in original row/column order (including hidden
columns), and briefly confirms success. Displayed cell text is copied without
HTML markup, with Markdown table separators and backslashes escaped.

Verification: 81 focused composer-table, cooked-table, Native context-menu,
Table and Data Table tests pass, with full static analysis. Native macOS checks
confirmed row menus without blue selection, insertion in the wide light layout,
deletion in the narrow dark layout, and the read-mode copy button/confirmation.
The local fixture now offers Read mode. No mobile device checks were performed.

### Typing performance (2026-09-18)

Reproduced with a 14-row, four-column table: five input changes rebuilt all 60
Native inputs each time (295 unrelated input rebuilds, 22,840 total widget
builds), taking 545 ms in an isolated debug widget-test run. Retaining the table
content across local text edits reduced the final run to 84 ms, 430 widget builds,
and zero unrelated input rebuilds. These are diagnostic host timings, not a
release-device frame-rate guarantee; the regression asserts rebuild isolation
for both headers and body cells instead of a flaky time limit.

Cell controllers own live text, selection and IME. Canonical Markdown still
updates synchronously on every keystroke. Structure changes, external source
updates/undo and submission state invalidate the retained content. Menus use a
structure/source version to reject stale callbacks while staying usable after
ordinary typing. Column resize actions use stable ordinal labels. Embedded
editors restore their normal selection colors independently of the outer
block's transparent selection range.

Native macOS verification used repeated individual key events in the large
table, then inserted a row through its context menu and typed in the new cell
in the narrow dark layout. All 101 focused table, selection and embedded-details
checks and full static analysis pass. The broader
draft-integration suite has four failures also reproduced on unchanged main
(three PM discard tests and the paused-typing save test); these are unrelated
to table rendering. No mobile device timing was measured.
