# Ten further improvements with deterministic proofs

Each change removes work that a real user path repeats. Every one has a proof
test that counts the work on that path and fails on its budget when the change
is removed. The counts come from [measurements.json](measurements.json), and
`tool/prove_perf_commits.py` reproduces them. Row cost comes from
[row-cost.json](row-cost.json).

## Results

Before and After are counts from the same proof test, with the commit's own
`lib/` change removed and then present. The fixtures are the full `AdaptiveShell`
or `DiscourseApp` tree over a fake API unless the row says otherwise.

| Improvement | Measured path | Metric | Before | After |
| --- | --- | --- | ---: | ---: |
| Composer title keystrokes | Costliest of 5 title keys, desktop | Elements rebuilt | 1,056 | 45 |
| | Costliest of 5 title keys, phone | Elements rebuilt | 599 | 43 |
| | Costliest of 5 caret-only moves, desktop | Elements rebuilt | 1,056 | 39 |
| | 5 caret-only moves in total | Draft saves sent | 1 | 0 |
| Composer draft bookkeeping | 5-key body burst, desktop | Elements rebuilt | 1,394 | 470 |
| | 5-key body burst, phone | Elements rebuilt | 928 | 385 |
| | The burst's successful save, desktop | Elements rebuilt | 1,000 | 7 |
| | Burst and save | Composer notifications | 3 | 0 |
| Mention and hashtag answers | Scripted `@` typing with a retype | User searches sent | 10 | 5 |
| | | Cooking context bumps | 10 | 3 |
| | Scripted `#` typing with a retype | Hashtag searches sent | 8 | 4 |
| | | Cooking context bumps | 8 | 1 |
| Thread detail on live replies | 10 replies, thread already held | Detail GETs | 10 | 0 |
| | 10 replies, only the root held | Detail GETs | 10 | 1 |
| Feed switch across a count change | One unread count change, desktop | Elements rebuilt | 2,755 | 819 |
| | One unread count change, phone | Elements rebuilt | 293 | 126 |
| | First frame after the change | Segments missing | 2 | 0 |
| Reader controls | One no-op shell notification, desktop | Control elements rebuilt | 176 | 0 |
| | One no-op shell notification, phone | Control elements rebuilt | 161 | 0 |
| Notification badges | One count change on another forum, iOS | Elements rebuilt | 1,071 | 70 |
| | One count change on another forum, macOS | Elements rebuilt | 868 | 69 |
| | Selected forum, steady state, iOS | Elements rebuilt | 1,084 | 321 |
| | Selected forum, steady state, macOS | Elements rebuilt | 879 | 130 |
| Incoming topics banner | 10 live `/latest` messages, macOS | Topic rows rebuilt | 230 | 0 |
| | | Elements per message | 696 | 192 |
| | 10 live `/latest` messages, iOS | Topic rows rebuilt | 40 | 0 |
| | | Elements per message | 205 | 108 |
| First composer | Launch, then open a new topic | `/site.json` requests | 2 | 1 |
| Tinted icon | One `DIcon` | Render objects | 5 | 1 |
| | One `DIcon` | Elements | 6 | 1 |
| | One topic row | Render objects | 343.1 | 330.4 |
| | One shown topic row | Retained KB | 1,559 | 1,525 |

The saved `/site.json` read is 357,376 bytes, or 57,674 gzipped, measured with
one anonymous GET of `https://meta.discourse.org/site.json` on 2026-11-08.

The row figures are `tool/topic_row_cost.py` on the same 17-row list, three
alternating runs per side. Render object and element counts were identical in
every run. Retained heap varied by at most 1.1 KB on one side. The limiter is
the 3.2 tinted icons in a row: the other 330 render objects are untouched, so
this change cannot do more than the 12.7 it removes.

## How often each path runs

Title keys and caret moves run on each key and each tap in a new-topic or
private-message title. The body burst and its save run on each typing pause.
Mention and hashtag searches run on each key while a trigger is open, and on
each later mention. Thread detail ran on every reply published in any open
channel's thread, because upstream publishes the preview event per reply.
Count changes follow `/new` and `/unread` traffic and finishing a topic.
Notification badges follow every `/notification` and `/reviewable_counts`
message on every connected forum. The banner follows every `/latest` or `/new`
message admitted to a visible list. Icons are mounted with each row and post on
every scroll, and stay retained.

A scripted 60-second read of an unread topic produced 31 shell notifications on
desktop and 19 on the phone, which is what the reader controls saving
multiplies by. Those two counts are the only frequencies this round measured.
The others come from reading the code and upstream, and nothing here measures a
live forum's event rate.

## What remains after each change

A rebuild or request that remains here is one the feature needs.

- A title key still rebuilds the field's own text and the tab label.
- A body burst still rebuilds the body editor's own listeners on its text.
- Mention and hashtag searches run once per distinct term per 30 seconds. Lookups
  always bump the cooking context, because they carry artwork.
- Thread detail still loads for an unmoved preview, which is how a rename or
  reply edit arrives. It also loads for the first read of a thread with no
  record, because unread projection needs its membership. A read already running
  is still dirtied so it cannot overwrite a newer preview.
- The feed switch's 819 elements are 717 for the switch itself, across two
  mounted selectors, and 102 other listeners.
- The reader's remaining 101 and 73 elements come from other listeners, such as
  `TopicPanelTabs`, `DesktopPanels`, and `UserPresenceMenu`.
- Another forum's badge costs only its own rail row. The selected forum costs the
  rail row, bell, and dock. The first message that creates a forum's totals
  still rebuilds the sections once, because plugins distinguish absent totals.
- The banner's remaining elements are the two banners on a 1440-wide desktop and
  other listeners under the shell scope.
- The dedicated `/site.json` read stays for an anonymous or failed category read,
  for a composer opened before that read lands, and for an account replaced
  mid-read.
- Multi-colour icons keep the `SvgPicture` path and its wrappers.

## Trade-offs each change accepts

- Mention and hashtag answers can be up to 30 seconds old. Core's autocomplete
  caches for the same 30 seconds, per
  `frontend/discourse/app/lib/user-search.js` and `hashtag-autocomplete.js`.
- A thread renamed while both held previews lag stays stale until the next
  unmoved event or until the thread opens. The web client applies only the
  preview on this event.
- A count that widens a badge uses the previous widths for one frame, then the
  measurement corrects it. Before this change that frame was a collapsed switch.
- Composer capabilities are as of launch rather than as of the first composer.
  The map already held them for the session.

## What this report does not claim

These proofs count work. They do not measure frame time, frame rate, or battery
draw, and they did not run on a device. An element rebuilt is a proxy for
UI-thread cost, so read these numbers as work removed.

## Reproduce the numbers

Run the proof tool from a checkout that contains the commits. It creates scratch
worktrees, runs each proof twice per side in alternation, and exits non-zero if a
proof passes without its change, fails with it, measures nothing, or varies
between rounds.

```sh
tool/prove_perf_commits.py docs/performance/ten-further-improvements-2026-11-08/manifest.json \
  --base 39d72c422 --out /tmp/proofs.json
```

## Verification of the combined branch

The ten commits were rebased onto `39d72c422` and checked as one tree.

- The proof tool reports all ten proofs hold, with zero failures.
- `flutter analyze` reports one info in `lib/src/data/byte_cache_store.dart`, also
  reported on `39d72c422`. Voice and `profiles/full` analyze clean.
- `dart format` flags `test/composer_autosave_span_test.dart` and
  `test/markdown_controller_regression_test.dart`. Both come from `118ecfd80`
  and neither is touched here.
- 409 test files covering the changed code ran 9,906 tests with 14 failures. The
  same 14 tests fail on unmodified `39d72c422`, compared by name, so this branch
  adds no failures. The repository's rules leave the full suite to CI, and it did
  not run here.
- Semantics dumps of topic rows, cooked posts, and the shell on macOS and iOS, 16
  dumps of 39,632 lines per side, show 0 changed lines from the tinted icon.
- A reviewer on a different model read all ten commits, tried to break each one,
  and reported no defects.

## Candidates this round did not take

`main` landed `93f971256` while this work was in progress, with the same
memoization of chat sidebar search text, so that candidate was dropped and the
mention cache took its place.

Scouts measured these and they stayed out, for the reason given.

- Writing scroll anchors after a scroll settles cuts 38 saves to about 5 in a
  20-second drag, and loses up to 5 seconds of position if the process is killed.
- Seeding a forum's first switch from its launch bootstrap saves two requests and
  lets the phone feed start without waiting on settings. It reverses the
  revalidation added in `9be169a69`, which is a product decision.
- Loading custom sidebar sections from the bootstrap user saves one request per
  launch and first switch, with a small change in section order.
- Fetching emoji aliases only on a catalog miss saves 47 KB gzipped, and delays an
  alias-only title by a round trip.
- These were measured and are still open: the phone shell chrome rebuilds 642
  elements per chat event, the idle chat composer takes 35% of a live arrival's
  rebuilds, the presence menu and panel tabs cost 102 elements per shell
  notification, the Categories page 742, and non-focusable focus scopes 8 render
  objects per row. Discover logos decode 14.9 MB where 188 KB would do.
