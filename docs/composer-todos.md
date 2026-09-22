# Composer to-do lists

Choose **To-do list** from the topic composer's `/` menu, or type `[]`, `[ ]`
or `[x]` at the start of a line. Closing the marker immediately creates the
item and adds its Markdown separator, so you can keep typing without adding
a space. Existing `[X]` and bullet-prefixed checklist lines also render with
Native `DCheckbox`. The editor retains Markdown, including inline formatting,
for copying, drafts and submission.

Click a checkbox or focus it and press Space to change its state. Completed
text is muted and crossed out; an empty item shows a “To-do” hint. Toggle and
insert commands have separate undo entries. Return starts an unchecked item,
Return on an empty item exits the list, Shift+Return inserts a plain line
break, and Backspace at the beginning of the item removes its checklist prefix.
Horizontal arrows and line-start commands skip the hidden marker. Code,
escaped markers and reference links retain their literal editing behavior.

The offline cooking owner includes the unmodified Checklist parser from the
same pinned Discourse revision as the rest of the bundle. Its site setting is
stored in the cooking owner's typed settings and projected per request.
Disabling `checklist_enabled` prevents checklist cooking, as upstream does.
The native saved-post renderer recognizes the plugin's `chcklst-box` HTML and
displays read-only Native checkboxes with completed text styling. Toggling a
saved post requires editing it; this change does not add server-side checklist
mutation. The insertion command is available in topic composers, not chat.

Verification includes source/parser tests, widget interactions, slash commands,
undo, source offsets, list reordering classification, narrow 200% text, stored
settings and the cooking corpus. The offline macOS fixture at
`tool/composer_todo_review_main.dart` mounts the production editor and saved-post
renderer. Light/narrow and dark/wide layouts, typing, Return continuation and
exit, and `/todo` insertion were inspected on macOS. Native accessibility
exposes the source editor as a text field and saved-post controls as checkboxes;
embedded editor checkboxes are not separate macOS accessibility elements.
