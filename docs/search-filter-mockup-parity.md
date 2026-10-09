# Search and filter refinements

Reference: `discourse-native-mockups` snapshot
`c39ad5079e36ccd40a2604c43b513195d5c125a2` (9 October 2026). This updates the
filter contracts in `search-mockup-parity.md` and `sidebar-filter-mockup-parity.md`.

| Source commits | Result in Native |
| --- | --- |
| `53f89c5`, `7368c87` | Topic-list filters use one grouped Native command sheet with number, calendar, tag and category editors. Categories browse one sibling level; subcategories are folded into the category picker. Global filters reuse the Native advanced editors for staged numbers, dates and multiple tags. |
| `67d3b1d` | Filter choices follow the active search scope. Messages have their own author, group inbox, date, media, extension and personal/direct filters. Existing user/group directory and plugin-owned Chat filters remain capability gated. Contains video uses the supported file-extension query. |
| `e4d461d` | Completed search syntax becomes editable chips while unfinished or invalid tokens remain in the input. Directory colon/equal syntax is parsed within its scope; each scope retains its own condition bank. |
| `6b2708f` | Closing search releases focus, preserves the draft and permits one-click reopening. Existing typed API parsing already tolerates non-text uploaded-media fields; no mock data or local post scanner is introduced. |
| `f4276da` | List category/tag pills open the same filter sheet at the relevant editor. Existing Native outside-click dismissal and route/account retirement are retained. Keyboard navigation scrolls only the command list, leaving the surrounding page in place. |
| `280e001` | Tag selection reserves its display area so rows stay in place. Match is one row, Done and Apply use the same Native size, and a selected tag has one visible mark. Backspace removes tags or steps through category exactness/ancestry. Search chips sort by localized field name and use Field: value labels, including significant operators. Tab and left/right switch search scopes from the appropriate input state. |
| `9eb8d4e`, `584ad71`, `04b4125` | Choices and results retain the production APIs, visible membership and authenticated permissions. User lookups show returned avatars and place the current user first. Author searches request individual matching posts. The final grouped column in `04b4125` supersedes the earlier alphabetical filter grid. |

All controls remain Native components. The approved `DCommand` adjustment
uses its own scroll position, leaves visible rows still, and allows actual
pointer movement to take over selection after keyboard navigation. A stationary
pointer cannot reclaim selection when scrolling or focus highlighting changes.
The separate non-embedded `TopicFilterInput`/`DCombobox` path remains supported.

## Production boundaries

- Topic-list clauses use the forum's `/filter.json` vocabulary, including its
  number/date names and comma/plus tag operators. Global search uses the separate
  search syntax. Neither syntax is substituted for the other.
- Message search uses the authenticated `/search.json` endpoint with
  `in:personal`, plus supported author, date, group and direct-message clauses.
  Mailbox folders remain message-navigation filters because this search
  endpoint has no folder operator. Administrator-only cross-user message search
  remains available through its existing permission-gated advanced filters.
- Video matches supported extensions (`mp4`, `webm`, `mov`, `m4v`, `ogv`, `avi`)
  through `filetypes:`. Embedded players without a matching indexed link/upload
  are subject to the server's search behavior; the app does not invent a
  `with:video` operator or scan downloaded posts.
- User and group filters keep the directory endpoints' supported semantics;
  plugin filters remain owned by their providers. The mockup's fabricated forum
  data, counts, people and client-side data scans are not production data sources.

## Verification

The explicit related search/filter suites passed 289 tests, including real
semantics labels and selection, keyboard/actual pointer movement, nested scroll
isolation, tag names containing spaces, number/date serialization, scope banks,
late lookup retirement, and feed/tab/forum/account ownership. Targeted Dart
analysis reports no issues. The full repository test suite was not run.

Real-font widget renders were inspected for a desktop light search, dark phone
search at 200% text, and desktop/phone list sheets at 200% text. The phone editor
scrolls to reach its remaining actions. These are rendered fixtures with API
request-shape coverage, not a physical-device or authenticated-server run.
Optional captures use `SEARCH_FILTER_CAPTURE=1` with
`test/search_filter_parity_test.dart`, and `SIDEBAR_FILTER_REVIEW_DIR` with
`test/sidebar_filter_parity_test.dart`.
