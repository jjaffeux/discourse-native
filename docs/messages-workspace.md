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

Native review on macOS used the isolated `MessagesReviewC584` debug app with
synthetic data. Inspected the wide split in light/dark palettes, next-message
activation, `g j`/`g k`, the 390px reader and collapse transition, a 390px list
at 200% text, the New message recipient dialog, and the Button styleguide.
No iOS/Linux device or authenticated account was used; iOS/macOS/Linux widget
variants cover the layout and navigation matrix.
