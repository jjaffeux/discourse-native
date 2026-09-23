# Composer to-do lists

Choose **To-do list** from the topic composer's `/` menu, or type `[]`, `[ ]`
or `[x]` at the start of a line. New items use `- [ ] ` Markdown list syntax.
Closing the marker creates the list item and its separator, so you can keep
typing without adding a space. Existing standalone `[ ]`, `[x]` and `[X]`
checklists remain supported without rewriting their source. The editor retains
the list markers and indentation for copying, drafts and submission.

A structured task owns its entire list-item body: wrapped lines, continuation
paragraphs, code blocks and nested lists all remain in the content column beside
the checkbox. The Native `DInput` in borderless growing mode edits a lossless
view of that body, mapping selection and composition back to the original
Markdown. Nested task editors share the enclosing document's undo history.
Images follow the task text without an extra paragraph gap when separated by
one source newline. Explicit blank lines are retained, and uploading an image
keeps the first line's text and checkbox in place.

Click a checkbox or focus it and press Space to change its state. Completed
prose is muted and crossed out; child tasks and code blocks retain their own
appearance. An empty item shows a “To-do” hint. Toggle and
insert commands have separate undo entries. Return starts an unchecked item,
Return on an empty item exits the list on the existing line without adding
an extra line break. An empty nested task moves out one level. Shift+Return
inserts an indented continuation; repeating it creates a paragraph in the same
task. Shift+Tab moves a nested task out one level, and Backspace at the beginning
of the item unwraps its body. Cmd/Ctrl+A in a task selects the enclosing
document, including its original Markdown when copied.
Horizontal arrows and line-start commands skip the hidden marker. Code,
escaped markers and reference links retain their literal editing behavior.

Each top-level task is a movable block, including an empty item.
Hover a row to use its drag handle, or use its move menu, keyboard shortcuts or
the mobile Arrange view. Moving a row retains its checked state, text, caret
and undo history without adding blank lines between consecutive to-dos. Moving
a task includes its paragraphs, code and nested items. Ordinary list parents
retain their descendants as one list block. Legacy standalone tasks still move
individually.

The offline cooking owner includes the unmodified Checklist parser from the
same pinned Discourse revision as the rest of the bundle. Its site setting is
stored in the cooking owner's typed settings and projected per request.
Disabling `checklist_enabled` prevents checklist cooking, as upstream does.
The saved-post renderer recognizes the plugin's `chcklst-box` HTML. For a task
list item, it replaces only the leading bullet/checkbox marker and renders the
complete remaining subtree beside the Native checkbox. Mixed lists retain
ordinary bullets, and nested tasks have independent completion state. When the
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
exposes the source and task-body editors as text fields and task controls as
checkboxes. No physical mobile-device or spoken screen-reader review is claimed.

The image-layout regression covers pending and completed uploads with Open Sans
and macOS system fonts, desktop/mobile widget layouts, and 100%/200% text. An
isolated macOS fixture also verified insertion in dark/wide and light/narrow
layouts using the image fallback preview. The focused todo/list/image suites
passed; five unrelated block-selection failures were reproduced on the unchanged
base revision.

Terminal images and galleries do not add a synthetic trailing caret line.
Selecting or deselecting an image leaves the next task in place; explicit source
line breaks remain intact. Regression tests cover this geometry and the image's
same-line end caret. A macOS fixture verified selection in dark/wide and
light/narrow layouts with the image fallback preview.

Return after an uploaded image reuses its empty continuation line for the next
item. Trailing spaces and indentation on a structural separator do not introduce
an extra row between tasks. Additional authored blank lines remain visible.

Todo checkbox artwork uses Native's `inlineTextStyle` to align with the first
text line while preserving the complete click target. Block actions follow the
same line, including empty placeholders, wrapped labels and legacy bare todos.
Regression coverage uses Open Sans and the macOS system font at 100% and 200%,
plus full-target activation on desktop and touch layouts. The isolated macOS
fixture verified empty and typed todos in dark/wide and light/narrow layouts.
Static analysis and 278 focused checkbox, styleguide, composer and posted-todo
tests passed. Touch coverage is from widget tests, not physical-device review.
