# Messages workspace

Messages uses the same inbox workspace as Topics. At widths of at least 880
logical pixels, selecting a message retains the resizable list on the left and
opens the existing topic reader on the right. The list header collapses the
reader. Narrow layouts retain the list offstage and put the collapse action in
the reader header.

The list footer contains New message and previous/next controls. The existing
`g j` and `g k` sequences open adjacent messages and continue into the next
page. The reader retains its topic footer, including Reply and Bookmark.
Folder and group changes retain an open reader in the split layout, and
navigation and composition use the selected message feed. The list keeps its
scroll state across opening and collapsing the reader.

All controls and rows reuse the existing Native components. No UI kit API was
added. `tool/messages_inbox_review_main.dart` mounts the production workspace
with offline message data, light/dark and narrow/large-text controls, and a link
to the styleguide.

Focused verification covers personal/group folders, restored inboxes, stale
menus, recipient validation, permission gating, split and narrow readers,
list retention, both footers, previous/next, keyboard navigation and pagination.
