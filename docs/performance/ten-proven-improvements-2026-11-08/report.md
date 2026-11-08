# Ten improvements with deterministic proofs

Each change below removes work that a real user path repeats. Every one has a
proof test that counts the work and fails on its budget when the change is
removed. The counts come from
[measurements.json](measurements.json), and `tool/prove_perf_commits.py`
reproduces them.

## Results

The Before and After columns are counts from the same proof test, with the
commit's own `lib/` change removed and then present.

| Improvement | Measured path | Metric | Before | After |
| --- | --- | --- | ---: | ---: |
| Sidebar keeps its build while reading | One tracking change, badge unchanged | Elements rebuilt | 1,454 | 0 |
| | One tracking change, one badge changes | Elements rebuilt | 1,455 | 45 |
| Search field ignores unrelated shell changes | One no-op shell notification, desktop field | Elements rebuilt | 70 | 0 |
| | One no-op shell notification, phone trigger | Elements rebuilt | 39 | 0 |
| Search capabilities load on first need | App start, search never opened | Requests | 3 | 0 |
| | Forum switch A to B to A | Requests | 6 | 0 |
| | First open of search | Requests | 0 | 3 |
| Chat transcript keeps its scroll position | 10 live messages | Positions replaced | 10 | 0 |
| Chat rebuilds only the rows that change | 10 live messages, 8 rows held | Tile builds | 135 | 19 |
| | | Elements rebuilt | 15,307 | 7,416 |
| Phone chat inbox stays still | 10 tracking events, off-screen channel | Elements rebuilt | 11,640 | 6,420 |
| | | Inbox rows built | 130 | 0 |
| Presence ticks skip unaffected avatars | 10 ticks for users not on screen | Frames scheduled | 10 | 0 |
| | | Avatar rebuilds | 30 | 0 |
| Relative times redraw together | 20 labels, 10 minutes | Frames | 200 | 20 |
| Covers decode at drawn size | User card, 1920x1080 at 2x | Decoded bytes | 8,294,400 | 1,557,504 |
| | Event card | Decoded bytes | 8,294,400 | 1,327,104 |
| | Event onebox | Decoded bytes | 8,294,400 | 921,600 |
| | Board card | Decoded bytes | 8,294,400 | 746,496 |
| | Badge symbol | Decoded bytes | 8,294,400 | 76,544 |
| Other notifications reuse `/site.json` | Load, then open the Other tab | `/site.json` requests | 2 | 1 |

The saved `/site.json` read is 357,376 bytes, or 57,674 gzipped, measured with
one anonymous GET of `https://meta.discourse.org/site.json` on 2026-11-08.

## How often each path runs

Sidebar tracking changes arrive up to twice a second while you read an unread
topic, and on each `/new` or `/unread` message. Search field notifications
follow every shell change. Search capability requests ran on every launch and
every forum switch. Chat row and scroll savings apply to every message in an
open channel or thread. The phone inbox saving applies to every message in any
followed channel. Presence ticks arrive on each enter or leave of any
chat-online user. Relative times wake whenever a list with recent labels stays
open. Cover decoding runs on each card, event, board, or badge render, and the
`/site.json` read ran once per account per launch.

These frequencies come from reading the code. Nothing in this report measures
a live forum's event rate.

## What remains after each change

A request or rebuild that remains here is one the feature needs.

- The sidebar's 45 elements are the changed row's own subtree.
- Search asks once per configuration when search opens, or when a closed field
  shows a list expression that a plugin filter may need to parse.
- The 19 chat tile builds are 10 new rows and 9 previous rows whose `endsGroup`
  value flips. The remaining 7,416 elements include the row wrappers above each
  kept tile.
- The phone inbox's 6,420 elements come from the panel tab badges and two other
  listeners outside the inbox.
- Each label really does change once a minute, so relative times still rebuild.
  They now do so in two shared frames a minute.
- The remaining `/site.json` is the category load's own read.

## Trade-offs each change accepts

- A relative time can lag its true change by up to 30 seconds. The web client
  refreshes every relative date on a single 60-second interval.
- Plugin search scopes appear one network round trip after the first open.
- Twenty-six sidebar rows each add a selector that runs on shell notifications.
  One notification costs 8 to 24 microseconds in the debug VM with 2,000
  tracked topics, from scratch timing that is not part of the proof.
- A kept chat tile holds the callbacks of the build that made it. Both stream
  hosts pass callbacks bound to their own State, so the callbacks stay current.

## What this report does not claim

These proofs count work. They do not measure frame time, frame rate, or battery
draw, and they did not run on a device. Load averages of 11 to 14 on 18 logical
CPUs ruled out timing as a proof here. An element rebuilt is a proxy for
UI-thread cost, so read these numbers as work removed.

## Reproduce the numbers

Run the proof tool from a checkout that contains the commits. The tool creates
scratch worktrees, runs each proof twice per side in alternation, and exits
non-zero if a proof passes without its change, fails with it, measures nothing,
or varies between rounds.

```sh
tool/prove_perf_commits.py docs/performance/ten-proven-improvements-2026-11-08/manifest.json \
  --base ac1dc7278 --out /tmp/proofs.json
```

## Verification of the combined branch

The branch was rebased onto `ac1dc7278` and checked as one tree.

- `dart format` passed. `flutter analyze` reports one info in
  `lib/src/data/byte_cache_store.dart`, which is also reported on `ac1dc7278`
  and is outside this change. Voice and `profiles/full` analyze clean.
- The full test suite passed 27,037 tests and failed 30. The same 30 tests fail
  on unmodified `ac1dc7278`, compared by test name with the failing files run
  on both, so the branch adds no failures.
- A reviewer on a different model read all ten commits, checked the stale-state
  cases each change could introduce, and found no bugs.

## Candidates this round did not take

Main landed `a95894226`, which removes the eager cooking runtime start, while
this work was in progress, so that candidate was dropped.

Scouts measured or traced these and they stayed out, for the reason given.

- Long-polling only the selected forum saves 96 to 54 polls over 10 minutes for
  four forums. It delays rail badges by up to 60 seconds, which is a product
  decision, and Voice rings need an exception.
- Dropping `include_topics` from warm category loads saves 33 KB gzipped on
  Meta, and costs an extra request when Categories opens.
- `UserPresenceMenu` and the topic header anchors cost 64 and 72 builds per
  shell notification, and `CategoriesPage` re-walks tracked topics on each one.
- Filtering chat in the sidebar re-parses each retained message on each
  keystroke, measured at 8.1 ms against 0.29 ms per pass with memoized text.
