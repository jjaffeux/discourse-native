# Bookmarks page parity

Reference: `discourse-native-mockups/src/App.tsx` at `13db54c`, the
`bookmarksView` page head and `BookmarkRow`. Colours are named by the mockup
token and the `DTokens` value that stands for it: `--primary` is the text
(`foreground`) and `--secondary` the ground (`background`).

The numbers below were read from the mockup served at 375 px wide with
`getComputedStyle` and `getBoundingClientRect`, and are pinned in
`test/bookmark_list_test.dart`.

| Part | Reference | Owner |
| --- | --- | --- |
| Head | One quiet pill as wide as its label: All bookmarks, Reminders, Expired | `_heading` in `bookmark_list.dart` |
| Rule | 1 px under every row but the last, places included | `DSeparator` |
| Row inset | 3 px start edge on every row, transparent unless expired | `BookmarkTile` padding |
| Expired row | 3 px accent edge and `--accent-tint` | `DItemSelectionStyle.leadingAccent` |
| Disc | 34 px circle, no outline, colour 25% into `--secondary` | `BookmarkTile` |
| Glyph | 14 px, colour 50% into `--primary` | `BookmarkTile` |
| Disc to text | 10 px | `DItem.gap` |
| Title | 14.5 / 1.35, weight 600, two lines | `DItemTitle(maxLines: 2)` |
| Details | 12.5 / 1.5, muted: note · kind · where | `BookmarkTile.details` |
| Padding | 12 px above, 14 px below (12 plus the row's 2 px margin) | `BookmarkTile` padding |
| Empty scope | "Nothing bookmarked here.", 13.5 / 1.5, muted, start-aligned, 24 px above and below | `bookmark_list.dart` |

Kinds read as the mockup names them: Topic, Post #N, Chat, Page and
Category. Where is the category, the chat channel, or the forum for a
bookmarked page or category. Icons: layer group for a topic, reply for a
post, comment for a chat, window for a page, tag for a category.

A filter pill draws its label at 14 px on a phone and 12.5 px elsewhere.
`DSelect` measures the label at the size it draws, so the pill never cuts
its own label short.

Pages, categories and chats bookmarked locally are drawn with the same tile
as server bookmarks and come first, as the mockup's own bookmarks do. The
Reminders and Expired scopes leave them out, since they carry no reminder.

The mockup marks an expired reminder only by its accent. The row's
accessible label still begins with "Reminder expired".

Kept beyond the reference: paging (Previous, Load more and the paging
skeleton), the first-load skeleton, Retry on a failed page, and the link
menu on each row. The reference has no live list to page through.

The user menu's Bookmarks tab is a different surface. It keeps its compact
rows; only the locally bookmarked places there use the page's tile, inset to
the menu's 16 px.
