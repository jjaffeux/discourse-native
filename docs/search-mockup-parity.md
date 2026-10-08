# Search parity

Reference: native mockup snapshot `54ba01c`.

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

The focused run has five baseline macOS assertions in
`test/message_inbox_page_test.dart`: three expect `new-message-button`, and
two expect the old list/footer navigation. All five fail identically on
unchanged main after the desktop title-bar port; the other message cases pass.
