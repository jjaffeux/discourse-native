# Ten reader and chat improvements with deterministic proofs

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
| Topic totals | One `stats` message, macOS | Elements rebuilt | 2,138 | 950 |
| | One `stats` message, iOS | Elements rebuilt | 2,128 | 702 |
| | One live reply, macOS | Elements rebuilt | 2,138 | 950 |
| Bookmark write | One bookmark, macOS | Elements rebuilt | 1,990 | 1,039 |
| | | Post tiles rebuilt | 5 | 1 |
| | One bookmark, iOS | Elements rebuilt | 2,108 | 919 |
| | | Post tiles rebuilt | 6 | 1 |
| Live post re-read | One like on a held post, macOS | Elements rebuilt | 423 | 323 |
| | | Shell selector runs | 57 | 0 |
| | One like on a held post, iOS | Elements rebuilt | 395 | 323 |
| | | Shell selector runs | 46 | 0 |
| Phone chat chrome | 10 tracking events, Chat tab | Elements rebuilt | 6,370 | 709 |
| | 10 messages, Forum tab | Elements rebuilt | 7,276 | 2,146 |
| Idle chat composer | 10 arrivals, channel, iOS | Composer elements | 2,570 | 0 |
| | 10 arrivals, channel, macOS | Composer elements | 2,550 | 0 |
| | 10 arrivals, thread, iOS | Composer elements | 2,570 | 0 |
| | 10 arrivals, thread, macOS | Composer elements | 2,550 | 0 |
| Categories page | One shell notification, phone | Page elements | 799 | 0 |
| | One shell notification, macOS | Page elements | 801 | 0 |
| | One tracking message, phone | Page elements | 799 | 67 |
| | One tracking message, macOS | Page elements | 801 | 67 |
| Presence menu | One notification, phone | Elements rebuilt | 72 | 9 |
| | One notification, macOS | Elements rebuilt | 100 | 51 |
| | 10 tracking messages, phone | Elements rebuilt | 720 | 90 |
| | 10 tracking messages, macOS | Elements rebuilt | 1,000 | 510 |
| Disk image cache | Warm launch, 40 avatars | File writes | 40 | 0 |
| | | Network requests | 0 | 0 |
| Draft autosave | 10 autosaves | Isolate spawns | 40 | 0 |
| | | `prefs.remove` calls | 20 | 0 |
| | | Directory listings | 20 | 0 |
| | | Fsynced replaces | 20 | 20 |
| Discover logos | Add Site sheet, 10 logos, 2x | Decoded bytes | 11,353,452 | 155,272 |

The commits are stacked, so a commit's numbers include the ones beneath it. The
Categories page's own total falls from 806 to 7 on a phone with the presence
menu already fixed beneath it.

## How often each path runs

Upstream publishes `stats` on `/topic/<id>` after every like, unlike, new post
and deletion (`app/models/topic.rb`), and a `liked` or `revised` message on the
post itself. Those two rows run per event in any open topic. Phone chat chrome
runs per message, tracking echo and read credit in any followed channel, on any
tab. The idle composer runs per message in the open channel or thread. The
Categories page and presence menu run per tracking message while on screen. A
bookmark write runs per toggle. The disk cache runs per image at each warm
launch, and each entry now costs at most one write a day. Draft autosave runs at
most every two seconds of typing. Discover logos run on first launch and when a
forum is added, so that one is a rare saving.

## Changes made during review

Three of the proofs as first written claimed more than they showed.

The first topic-totals key listed the fields it believed tiles read. An audit
found `post_voting_plugin` reads `closed` and `nested_replies_plugin` reads
`canEdit`, neither in the list, and any later field would have been missed in
silence. The key now compares every field except a named set of figures, and
`TopicDetail`'s equality is built from the same list, so a new field is covered
by default. `topic.stream` is a figure, so Solved now reads the visible topic
when its action runs.

The bookmark proof's fake forum omitted the topic-level bookmark list that a real
forum returns. Against an accurate payload every tile still rebuilt. A tile reads
only the topic-level bookmark, so the key now compares that one, and the proof's
fixture reports the bookmark as a forum does.

The scout's claim that only a removal needs the shell notification was wrong.
Selected posts and plugin readers also depend on it, and both keep it.

## Limits

These are counts of work on a fake API, in debug test builds. No frame timings
and no device runs back them. A count shows that work stopped, and the frame or
battery gain it buys is inferred.

The live reply row's fixture changes only the post stream and totals. A real
topic read can also change compared fields such as suggested topics, which would
rebuild the tiles for that reply.

Draft autosave's release-build gain per codec call is small, 3 to 10 microseconds
inline against 32 to 37 isolated. It saves energy and save latency, and no frame
was at stake.

## Verification

`dart format`, `flutter analyze` for the app, Voice and the compatibility
profile, and 38 covering test files were run on the rebased branch. Eight tests
in `chat_shell_integration_test` and `topic_view_lifecycle_test` failed, and the
same tests fail on the base commit. The channel-corners tests among them fail
only under some shuffled orders, and fail on both sides when the same seed is
replayed. Nothing failed only on this branch.
