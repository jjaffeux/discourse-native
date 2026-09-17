# Topic card design studies

Three interactive HTML/CSS alternatives for card mode. This folder is a design
artifact; it does not change the Flutter application or its compact list.

The selected direction is **B — Conversation cards**. The native implementation
is in `lib/src/shell/conversation_topic_card.dart`: Card owns the surface/footer,
and Item owns immediate hover and outlined selection. Sortable fields remain in
the cards; table headings belong to Compact mode. When a topic is visible beside
its source list, the list temporarily uses cards and the display choices are
locked to Card. Closing the topic or switching to a dialog restores the saved
display preference without replacing the list's controllers.

Run from the repository root:

```sh
python3 -m http.server 8778 --bind 127.0.0.1 --directory docs/mockups/topic-cards
```

| Direction | Preview | Design tradeoff |
| --- | --- | --- |
| A — Framed rows | http://127.0.0.1:8778/?design=framed | Individual bordered surfaces with internal padding, retaining aligned table columns. Familiar scanning, but the smallest departure from a list. |
| B — Conversation cards | http://127.0.0.1:8778/?design=conversation | Full-width cards with taxonomy, title and assignment above a separate people/activity footer. Preferred direction for a clear card treatment and predictable vertical reading order. |
| C — Card grid | http://127.0.0.1:8778/?design=grid | Responsive tiles with aligned footers. More visual separation, with more horizontal eye movement when scanning titles. |

The direction tabs preserve the current preview context, theme and width.
Preview controls below the app pane provide light/dark themes, a 390px pane,
messages, assignments, aggregate forums, signed-out mode, and loading/empty/error
states. The grid uses as many columns as the available width permits. All
directions collapse into a single column in a narrow pane.

## Preserved behavior

- Outlined feed/category/tag triggers; transparent header and footer actions.
- Feed counts aligned at the trailing edge and Top periods inside the feed menu.
- Category/subcategory colors, tags and overflow, assignment details, unread/new
  markers, visited titles, bookmark/pin colors, and event dates/schedules.
- Category badges and tags share the card's top line, wrapping as needed.
- Neutral filled hover and outlined selection, without tag hover transitions.
- Larger text, topic preview beside the list or in a dialog, topic
  navigation, new topic and saved drafts.
- Existing sample filter autocomplete and filtering, forum and assignee filters.
- A retains sortable column headings. B and C expose Replies and Activity
  field headings in their footers.
  Assigned cards also expose Views. Unsupported sorts remain passive.

`base.css` and `base.js` reuse the earlier topics-table prototype; `cards.css` and
`cards.js` define the new card presentations. All content and interactions are
local sample data. Creation, tracking, pagination and reader content are simulated;
there are no forum requests or persisted account changes.

## Native implementation mapping

Use `DCard` for surfaces and `DCardFooter` for the divided footer, with `DItem`
owning interaction/selection. Keep existing Native buttons, menus, badges,
taxonomy, event and assignment components. Consult the Card and Item catalogue
entries when implementing the chosen direction; prototype CSS is not a substitute
for their tokens, geometry or accessibility behavior.

## Verification

- JavaScript syntax checks for both scripts.
- Browser review of all three directions, including a 390px pane and light/dark
  treatments. Checked wider grid layout and assigned-card wrapping; no card or
  document horizontal overflow in inspected layouts.
- Exercised sorting, event details, feed counts/periods, and display options.
- No browser console warnings or errors during the review.
