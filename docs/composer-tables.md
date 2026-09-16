# Composer tables

Use **Insert → Table** to insert a two-column table, or open a post/draft that
already contains a rectangular Markdown pipe table. Headings and body cells are
editable in place. The editor composes the same `DDataTable.softHeader` variant
as cooked posts, with Native inputs, menus and buttons.

- Column menus insert before/after, move earlier/later, and delete columns.
- Numbered row menus insert above/below, move up/down, and delete body rows.
- **Add row** and **Add column** append to the table. The header stays first,
  and deleting the last column is disabled.
- Tab/Shift+Tab move between cells; advancing past the last cell adds a row.
  Enter/Shift+Enter move within a column. Escape or **Done** returns to prose.
- Native selection, clipboard and undo shortcuts act on the focused cell.
  Bold, italic and code shortcuts insert Markdown in that cell.
- Column resizing is local presentation state; column ordering changes the
  source. Wide tables scroll horizontally.

Every accepted change synchronously updates the composer's canonical Markdown,
so drafts and submission use the same source as other composer edits. Cell edits
replace only that cell's content. Row moves retain authored lines; column moves
carry cell contents and alignment markers together. Column changes can add
boundary pipes to a table authored without them. Pasted pipes are escaped and
cell line breaks become `<br>`.

Recognition is deliberately limited to rectangular pipe tables, including
header-only and single-column tables. Malformed/ragged tables, quoted/list
tables, fenced or indented code, and HTML remain ordinary source. Active main
editor IME composition defers projection. Table edits reject stale source and
inactive/submitting composer sessions.

`ComposerInteractiveSyntaxProjection` preserves the table widget's identity
across its own edits and gives its nested controls pointer/keyboard ownership.
`ComposerEmbeddedEditor` keeps native cell text actions from resolving to the
surrounding composer, and groups accessibility traversal outside the main text
field. These changes compose existing Native components without extending the
UI kit.

## Verification

`test/composer_tables_test.dart` covers source parsing and transformations.
`test/composer_table_test.dart` mounts the real composer and checks menus,
keyboard navigation, cell focus/composition, paste, undo/redo, source drift,
submission locking, accessibility traversal, and narrow layouts at 200% text
in light/dark themes.

The 28 table-specific tests pass, as do the accompanying composer, cooked-table
and Native control-adoption regressions. Six existing image/gallery tests in
`composer_upload_panel_test.dart` fail identically on unchanged `38dbf0df`
(toolbar overflow and obsolete control finders). Focused static analysis and the
macOS debug build pass. Final native keyboard/accessibility review remains
pending because the desktop was locked, then held by another review task.

For native review, run the in-memory fixture without a forum account:

```sh
flutter run -d macos -t tool/composer_table_review_main.dart
```

The fixture includes narrow/wide, light/dark and RTL controls, plus a link to the
component styleguide. It uses fake API and draft storage.
