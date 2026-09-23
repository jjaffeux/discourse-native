# Composer bulleted and numbered lists

Choose **Bulleted list** or **Numbered list** in the `/` menu, or type `- `,
`* `, `+ ` or `1. ` at the beginning of a line. The separating space switches
to an editable list item. Empty items show a “List” hint. The commands also
convert the current item between list types, retaining its text and descendants.

Return splits the item at the caret and focuses the next item. Numbered items
continue counting automatically. Return on an empty item leaves a paragraph;
on an empty nested item it moves out one level. Shift+Return adds a continuation
inside the item. Tab nests an item under its preceding sibling; Shift+Tab moves
it out. Backspace at the beginning moves a nested item out or turns a top-level
item into a paragraph. Top-level items can be moved through the existing block
handles and move menus, including their descendants.

The existing Native `DInput` and `DCommand` compositions own editing and slash
commands. List markers are text beside the input; to-dos continue using the
Native checkbox. Nested and mixed lists keep compact spacing, while explicit
blank lines retain paragraph spacing. Drafts, copying and submission use the
original Markdown. Displayed numbering follows the first marker in each list,
including pasted lists that repeat `1.`. Unedited marker values are retained.
Lists inside code fences stay literal, and composing a marker does not replace
the active IME input. Topic, personal-message and taxonomy composers share
this behavior; plugin-owned composers retain their own syntax policies.

Verification: focused parser and widget coverage includes slash insertion,
typing shortcuts, conversion, Return, exit followed by typing, Shift+Return,
nesting, Backspace, moves, undo, CRLF, IME, mixed lists, 200% text and to-do
regressions. The offline macOS fixture is
`tool/composer_lists_review_main.dart`; it mounts the production composer and
saved-post renderer. The native review covers dark/wide and light/narrow layouts,
typing, continuation, empty-item exit and slash insertion. No physical mobile
device or spoken screen-reader testing is claimed.

The existing `composer_details_rich_test.dart` case “clipboard upload is
cancelled when its disclosure is removed” fails because its “Delete details”
menu item is absent. This also reproduces on unchanged main (`2c1c71617`); it is excluded from the passing regression run.
