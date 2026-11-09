# Ten request, disk and render-weight improvements with deterministic proofs

Each change removes work that a real user path repeats. Every one has a proof
test that counts the work on that path, fails its budget when the change is
removed, and asserts that the user still gets the correct result. The counts
come from [measurements.json](measurements.json), and
`tool/prove_perf_commits.py` reproduces them from
[manifest.json](manifest.json).

## Results

Before and After are counts from the same proof test, with the commit's own
`lib/` change removed and then present, two alternating rounds per side. Every
round gave identical numbers. The tool reverse-applies one commit at a time on
the final stack, so each row is that commit's own contribution.

| Improvement | Measured path | Metric | Before | After |
| --- | --- | --- | ---: | ---: |
| Likes on an open topic | Ten likes by other readers on one post | Post reads | 10 | 0 |
| | | Response bytes | 17,020 | 0 |
| | The echo of the reader's own like | Post reads | 1 | 0 |
| Saved bookmarks | Create on a post | Topic reads | 1 | 0 |
| | | Response bytes | 29,646 | 0 |
| | Create on a topic | Topic reads | 1 | 0 |
| | Edit | Topic reads | 1 | 0 |
| | Delete | Topic reads | 1 | 0 |
| | Clear a topic | Topic reads | 1 | 0 |
| Heading anchors | Each Markdown heading | Render objects | 21 | 3 |
| | | Elements | 53 | 10 |
| Code fences | A 30-line fence | Render objects | 262 | 83 |
| | Each further line | Render objects | 6 | 0 |
| | | Elements | 12 | 0 |
| Desktop image bars | Each image in a post, macOS | Render objects | 40 | 23 |
| | | Elements | 86 | 54 |
| Idle chat composer | Ten messages in the open channel, iOS | Composer elements rebuilt | 2,600 | 0 |
| | Ten messages in the open channel, macOS | Composer elements rebuilt | 2,580 | 0 |
| | Ten replies in the open thread, iOS | Composer elements rebuilt | 2,600 | 0 |
| | Ten replies in the open thread, macOS | Composer elements rebuilt | 2,580 | 0 |
| Scrolling writes | One continuous scroll of a topic list | Document writes | 20 | 1 |
| | | Bytes written | 11,332 | 567 |
| | One continuous scroll of a topic | Document writes | 20 | 1 |
| | | Bytes written | 17,778 | 888 |
| Phone navigation writes | Five topic opens and five backs | Document writes | 20 | 10 |
| | | Bytes written | 30,861 | 15,570 |
| Date countdowns | A countdown days away, five minutes | Frames | 300 | 5 |
| | | Timers armed | 300 | 5 |
| Search panel | Open on the Tags page, macOS | Page elements rebuilt | 601 | 0 |
| | Open on the Tags page, iOS | Page elements rebuilt | 549 | 0 |
| | Close on the Tags page, macOS | Page elements rebuilt | 601 | 0 |
| | Close on the Tags page, iOS | Page elements rebuilt | 549 | 0 |
| | Open on the topic list, macOS | Page elements rebuilt | 610 | 0 |
| | Open on the topic list, iOS | Page elements rebuilt | 280 | 0 |

Bytes are uncompressed fixture bodies. The fixtures follow the upstream
serializers: `likes_count` and `user_id` from `PostActionCreator`, a 20-post
topic for bookmark reads.

The image proof holds its request open. A widget test answers every network
request with an error, and a failed image is `BrokenImage`, which has no
metadata bar. A pending request leaves the same tree a loaded image has.

## What changed for readers

Likes and bookmarks now behave as the web client does. A like applies the
count the message carries, and a saved bookmark projects the write's own
answer. A read remains where the message cannot answer: a viewer who ignores
users, a message with no count, a write or read already out, a bookmark whose
outcome is unknown, and a post bookmark this account cannot number.

Long posts with headings, code and images keep fewer objects alive, which is
what drives the garbage collection behind dropped scroll frames, as
[topic-row-composition.md](../topic-row-composition.md) records.

A scroll now writes the tab document once, 500 ms after it rests. Backgrounding,
quit, disposal and view teardown still flush the pending anchor. A crash during
a continuous scroll restores the position from before that scroll.

## Reviewer decisions

- A code fence is now one text node with newlines, where it was one node per
  non-blank line, so a screen reader stops once per fence. Fences over 100 lines
  already behaved this way. The change also fixes copying: a selection across
  lines used to lose its line breaks.
- A heading's semantics node no longer exposes tap and long press, which only
  scrolled the heading to itself.
- Tests changed with the behaviour. `bookmark_shell_controller_test` expects two
  topic reads instead of three. A race in `posted_todos_test` now runs on an
  unreachable create, the path that still reads. Six exact-text finders in the
  code block tests became `find.textContaining`, because a line is no longer its
  own `Text`. `chat_uploads_accessibility_test` no longer asserts that invisible
  text is mounted before hover. `coalescing_snapshot_writer_test` gives its
  queued-save case a turn between the two saves, and a new test pins that two
  saves in one turn make one write.

## Verification

Format and `flutter analyze` pass for the root, `packages/discourse_voice` and
`profiles/full`. All 372 test files that mention a changed class ran on the
stack before its last two rebases: 9,004 passed, 2 were skipped and 6 failed.
Each of the six failed the same way on the untouched base in two alternating
rounds per side, so this stack added no failure. The six are
`control_style_adoption_test`, one case in `keyboard_navigation_test`, two in
`phone_chat_chrome_rebuild_test`, and two in
`site_image_playback_visibility_test`.

## Candidates this round did not take

Proven on a branch, and left out so this round holds ten:

- Browse channels redraws for every chat message: 29,371 elements against 1,511
  over ten messages, on `claude/perf4-chatlong`. Readers rarely rest on that
  page.
- A category filter walks the category list per parent: 273,109 id reads against
  3,409 at 500 categories, on `claude/perf4-algo`. It costs about a millisecond.

Measured, and needing a decision or a better proof:

- A long draft is walked seven times per keystroke for literal source, 7.15
  against 1.15 walks through the real composer with a temporary counter. The
  commit on `claude/perf4-algo` simulates the parser reads in its proof, so it
  was not counted here.
- A leaderboard builds all 100 rows on open: 9,755 elements against 867 on
  `claude/perf4-routes`. Lazy rows cannot measure columns across all rows, so
  Rank and Cheers stop sharing spare width on wide windows. That is a visible
  layout change.
- A report table builds every row eagerly: 36,674 elements at 1,000 rows. A lazy
  table needs fixed column widths or paging.
- A channel's thread list and My Threads rebuild for every message: 6,100 and
  4,890 elements over ten messages.
- Mention and hashtag pills cost about 33 and 40 render objects each, inside kit
  components that other surfaces share.

Measured and rejected: idle frames and timers, which are already zero in a real
session on the list and in the reader, and writes across background and resume
cycles, also zero.
