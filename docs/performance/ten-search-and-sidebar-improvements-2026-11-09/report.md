# Ten search and sidebar improvements with deterministic proofs

Each change removes work that a real user path repeats. Every one has a proof
test that counts the work on that path and fails its budget when the change is
removed. The counts come from [measurements.json](measurements.json), and
`tool/prove_perf_commits.py` reproduces them from
[manifest.json](manifest.json).

## Results

Before and After are counts from the same proof test, with the commit's own
`lib/` change removed and then present, two alternating rounds per side. Every
round gave identical numbers. The fixtures are the full `AdaptiveShell` over a
fake API unless the row says otherwise.

| Improvement | Measured path | Metric | Before | After |
| --- | --- | --- | ---: | ---: |
| Unchanged search | Eight paused steps, words mostly unchanged | Searches sent | 24 | 3 |
| | A trailing space | Searches sent | 3 | 0 |
| | A trailing space | Elements rebuilt | 1,296 | 828 |
| | First search of the session | Searches sent | 3 | 3 |
| Search field | One keystroke while loading, desktop | Elements rebuilt | 442 | 66 |
| | | Scope bar elements | 155 | 0 |
| | | Skeleton elements | 78 | 0 |
| | One keystroke while loading, phone | Elements rebuilt | 494 | 72 |
| Search result rows | Second source answers | Elements rebuilt | 664 | 421 |
| | | Row elements | 313 | 70 |
| | Last source answers, nothing changes | Elements rebuilt | 503 | 192 |
| | | Row elements | 311 | 0 |
| Sidebar navigation | Open a topic | Elements rebuilt | 1,596 | 68 |
| | | Sidebar tiles rebuilt | 28 | 0 |
| | Close a topic | Elements rebuilt | 1,596 | 68 |
| | A sidebar click | Elements rebuilt | 1,608 | 220 |
| | | Sidebar tiles rebuilt | 28 | 2 |
| Sidebar after a count | Next tracking message, macOS | Sidebar elements | 480 | 68 |
| | | Elements rebuilt | 776 | 364 |
| | Next tracking message, iOS | Sidebar elements | 522 | 68 |
| | | Elements rebuilt | 1,255 | 801 |
| Notifications panel | One live count, macOS | Elements rebuilt | 2,324 | 513 |
| | | Rows rebuilt | 15 | 0 |
| | One live count, iOS | Elements rebuilt | 2,145 | 758 |
| | | Rows rebuilt | 18 | 0 |
| Bookmarks page | One tracking message, macOS | Section elements | 1,019 | 0 |
| | | Elements rebuilt | 1,114 | 95 |
| | One tracking message, iOS | Section elements | 882 | 0 |
| | | Elements rebuilt | 1,168 | 286 |
| Bookmarks menu tab | One tracking message, macOS | Elements rebuilt | 330 | 96 |
| | One tracking message, iOS | Elements rebuilt | 116 | 54 |
| Composer undo and redo | One body key, desktop | Elements rebuilt | 103 | 63 |
| | One body key, phone | Elements rebuilt | 86 | 47 |
| | Ten keys | Undo button builds | 10 | 0 |
| Inline link menu | Topic of linked paragraphs, macOS | Render objects | 1,266 | 1,098 |
| | Topic of linked paragraphs, iOS | Render objects | 1,417 | 1,201 |
| Retained list labels | Second topic open, macOS | Elements rebuilt | 3,578 | 3,288 |
| | | Widgets invalidated | 61 | 0 |
| | Second topic close, macOS | Elements rebuilt | 2,075 | 1,835 |
| | | Widgets invalidated | 55 | 0 |

The commits are stacked, so a commit's numbers include the ones beneath it.

Retained heap for the inline link menu was measured separately, on 12 copies of
a four-paragraph post with four forced collections per sample: 461 KB to 276 KB
per post on macOS. The proof tool does not reproduce that figure.

## How often each path runs

Search runs per keystroke and per source answer. The sidebar navigation row runs
per topic open, close and sidebar click. The sidebar count row runs on the next
tracking message after any count change. The notifications panel runs per live
count or reviewable message while it is open. The Bookmarks rows run per tracking
message while the page or tab is open. Composer undo runs per body key. The link
menu is paid for every paragraph with a link as it scrolls into a list. Retained
list labels run per topic open and close.

## Decisions an implementer changed

The scout's Bookmarks selector left a renamed chat channel stale, shown by a
mutation test. The page now compares what it would draw, so it still re-presents
each loaded row on a notification and rebuilds only when a row differs. CPU for
that comparison remains, and only the rebuilds are gone.

Mounting the link menu on the first press, as the scout proposed, broke the
accessibility tree. Its popup nodes were reported as detached on first open on
macOS and iOS, and never joined the tree. Keeping one enabled `Semantics` node
in the idle state fixes it. Full semantics dumps at closed, first open, reclosed,
reopened and after a long press match the base tree except for the
`traversalParentIdentifier` line on paragraphs whose menu never mounted.

The Categories and Bookmarks end-of-list checks relied on shell notifications to
page on a taller window, so both now follow scroll metrics.

## Limits

These are counts of work on a fake API, in debug test builds. No frame timings
and no device runs back them. A count shows that work stopped, and the frame or
battery gain it buys is inferred.

Retained list labels save 8% on open and 12% on close, and the close saving
applies only when the list is retained, which the default two-list workspace
does not do today. An overloaded forum that answers a search with 200 and no
results now counts as answered until Enter, Retry or a change of words.

## Verification

`dart format`, `flutter analyze` for the app, Voice and the compatibility
profile, and 54 covering test files were run on the rebased branch. Nine tests
failed. Eight of them fail identically on the base commit, in
`chat_shell_integration_test`, `connection_session_integration_test`,
`keyboard_navigation_test` and `search_filter_parity_test`. The ninth is the
`chat_shell_integration_test` channel-corners test, which fails only under some
shuffled orders and did so on main in the previous report's seed replay. Nothing
else failed only on this branch.

## Candidates this round did not take

Measured, and left for a decision or a later change:

- A live reply makes a full topic read, 22 KB on a long Meta topic, where the web
  client reads one post at the end of the stream, 3.8 KB. A prototype removed the
  full read and failed 7 tests, most of which use `created` as a read trigger.
- A like re-reads its post, where the web client applies the payload's count.
- A successful bookmark write reads the full topic, where the web client syncs
  locally.
- In the default two-panel workspace, Back to list closes the tab and remounts
  the list, losing its scroll position. That is a behavior defect as well as
  about 1,143 elements.
- A personal-message count change rebuilds every sidebar section: 1,567 elements
  against 246 in a prototype.
- Desktop image metadata bars mounted at opacity 0 cost 19 render objects per
  image. Unnumbered code lines cost 5 render objects each where 2 would do.

Measured and rejected: a cooked HTML parse cache, because scrolling back 32,000
pixels reparsed 58 strings for about 0.8 ms in total.
