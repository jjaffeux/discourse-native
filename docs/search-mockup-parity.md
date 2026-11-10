# Search parity

Reference: native mockup snapshot `54ba01c`. Title-bar input styling was
rechecked against `c39ad50`.

The input uses Native's search variant: a 36px desktop capsule, recessed
light/dark fill and inset edges, 14px side padding inside the 1px border, 8px
gaps, a 16px leading icon, and a single compact shortcut badge. The icon stays
before filter chips. The 12px clear glyph owns exactly its visible bounds and
remains available for filter-only searches. Filters change the placeholder to
“Add words or filters…”. The opened field shares the popover's 14px corners,
with 5px added above and below the stationary editor. The surface follows the
field width; very narrow anchors retain a viewport-bounded results surface.
Text scaling, mobile sizing, platform shortcut labels, and Native keyboard and
focus behavior remain supported.

The search appearance regression renders closed, open, populated and filtered
states in light/dark at 100% and 200%. Set `SEARCH_INPUT_CAPTURE_DIR` when running
`test/search_input_appearance_test.dart` to export real-font widget captures.
These are fixture renders, not an authenticated app or physical-device run.

This port follows `88bb68c`, `25184f6`, `4f08809`, `107d9bb`, `2fa345e`,
`4d045d0`, and `54ba01c`. The latest snapshot supersedes the earlier layouts.

- The title-bar field and Cmd/Ctrl-F share one anchored Native surface. Closing
  shows the focused list's scope; reopening keeps an unfinished query and its
  caret. Scope changes on another page seed that page's current filters.
- Empty searches offer removable recents and available filter keys. Recents
  retain legitimate word searches, with removals saved per forum/account.
  Typed keys stage live choices in the sheet, including keyboard navigation,
  nested category browsing, paging, replacement, ordering, and backspace editing.
  Existing advanced pickers retain their operators and plugin capabilities.
- Results use plain section headings, aligned compact rows, excerpts around
  matches, and accent markers. Category and tag matches use their filter-row
  marks, available parent information, and server-provided counts.
- Context orders results while keeping other kinds available. Reading a topic
  adds a separate server query ahead of the global results; its heading opens
  the first hit and individual rows open their exact posts with a brief flash.
- Enter applies words and filters to a native list. Ordinary word searches keep
  its mode and taxonomy; advanced search operators use a list backed by the
  search endpoint. Message section headings search the account's personal
  messages, and directory/chat headings open their native pages with the words.
- Markers follow the owning forum, tab, and page across topic/message lists,
  readers, rich content, code, directories, and chat. Account retirement clears
  them. Chat search rows show their matching excerpt and open the matched message.

Production results and lookup choices come from the existing authenticated
APIs and plugin providers. Search words are separate from category, tag, and
author filters. The server's tokenization, minimum length, permissions, and
matching behavior remain authoritative. In particular, ordinary list word
searches and advanced search operators use their respective server endpoints;
the latter are not sent as list-filter syntax. See the upstream
[topic query](https://github.com/discourse/discourse/blob/main/lib/topic_query.rb)
and [search implementation](https://github.com/discourse/discourse/blob/main/lib/search.rb).

Focused regressions cover the search session, response parsers, navigation,
lookups, keyboard flow, persistence, reader highlights, and touched Native
pages. Real-font widget captures were reviewed at desktop and phone widths,
light/dark, and 200% text. They are focused widget renders with wire-shaped
test responses; no physical-device or authenticated live-server run was made.
The Native surface renderer belongs to the separate glass/depth group.

## Folded filters and row details (`13db54c`)

Rechecked against `7f43e9d`, `6542d02` and `13db54c` on `test-mobile-layout`.

- Under an empty field the filters wait folded behind a "Filters" row with a
  chevron, closed each time search opens. The row opens and closes on a press,
  on Enter, or on the right and left arrows. Those arrows reach a row's own way
  sideways before they switch search types. While a word that could start a
  filter is being typed, the matching filters stand open under a plain
  heading.
- "Recent searches" and "Filters" are 32-point headings with their mark in
  the rows' 30-point mark column. Past searches have no icon of their own and
  start under the heading's label. A typed word narrows them, and Clear
  history hides while it does.
- Each filter row is 38 points tall, with its icon in a raised 30-point circle
  and its help text beside its name on the same line.
- "In this topic" is bold, the topic's title follows in muted text, and the
  heading ends in the navigation pill. Its post rows centre a 22-point face in
  the 30-point column.
- Chat results use the message layout that plugin scopes can now declare
  (`GlobalSearchResultLayout.message`): two lines of what was said, the
  channel as `#name` or "Direct message" under them, and the date beside the
  row. At large text the date returns to the details line.
- Search-type counts stop at 99+. The details line's separators are half as
  strong as its text and are not read aloud. While a category is browsed, the
  desktop footer says "← → Into a category" in place of "Tab Next type".

- The phone's search field is 44 points tall, as `.phone-search`'s field is,
  so what it finds starts 8 + 44 + 8 points under the screen's top. The head
  is wrapped in `DTouchFields`, and `DInputGroup` now follows that rule as
  `DInput` already did.

Return on a phone still keeps search open and only closes the keyboard, as
`1c17b226e` chose; the mockup opens the highlighted row.

The focused run has five baseline macOS assertions in
`test/message_inbox_page_test.dart`: three expect `new-message-button`, and
two expect the old list/footer navigation. All five fail identically on
unchanged main after the desktop title-bar port; the other message cases pass.
