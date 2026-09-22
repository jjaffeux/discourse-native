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
Return on an empty item exits the list and inserts a line break, leaving a
blank line after the previous item. Shift+Return inserts a plain line break,
and Backspace at the beginning of the item removes its checklist prefix.
Horizontal arrows and line-start commands skip the hidden marker. Code,
escaped markers and reference links retain their literal editing behavior.

Each standalone to-do line is its own movable block, including an empty item.
Hover a row to use its drag handle, or use its move menu, keyboard shortcuts or
the mobile Arrange view. Moving a row retains its checked state, text, caret
and undo history without adding blank lines between consecutive to-dos.
Bulleted Markdown lists retain their complete nested structure as list blocks.

The offline cooking owner includes the unmodified Checklist parser from the
same pinned Discourse revision as the rest of the bundle. Its site setting is
stored in the cooking owner's typed settings and projected per request.
Disabling `checklist_enabled` prevents checklist cooking, as upstream does.
The saved-post renderer recognizes the plugin's `chcklst-box` HTML. When the
server grants `can_edit`, its checkboxes are interactive and update immediately.
The client uses Discourse's `/checklist/toggle.json` endpoint with the current
raw source and timestamp, a mutation ID, and each checkbox's source location
(or its rendered index and count for older cooked HTML). It fetches the source
after projecting the click and rejects stale content before sending the write.
Rapid clicks are queued per post and persisted in order. A rejected batch rolls
back to the last confirmed state; conflicts refresh the post. A lost response
is reconciled by reading the server, while an offline, uncertain outcome keeps
the optimistic view and reports that saving could not be confirmed.

Quoted checkboxes, permanent `[X]` markers, revision diffs, localized bodies and
posts without edit permission stay read-only. Nested details, spoilers and
tables retain whole-post checkbox indices and their presentation state through
toggles. Bookmark changes can save independently while a checklist is saving;
bookmark reconciliation changes only bookmark metadata. Live post refreshes
wait until both writes finish, and responses from a retired account cannot change
the current post. The insertion command is available in topic composers, not chat.

Verification includes source/parser tests, widget interactions, slash commands,
undo, source offsets, individual row dragging and mobile movement, narrow 200%
text, stored settings and the cooking corpus. The offline macOS fixture at
`tool/composer_todo_review_main.dart` mounts the production editor and saved-post
renderer. Light/narrow and dark/wide layouts, typing, Return continuation and
exit, and `/todo` insertion were inspected on macOS. Native accessibility
exposes the source editor as a text field and saved-post controls as checkboxes;
embedded editor checkboxes are not separate macOS accessibility elements.
