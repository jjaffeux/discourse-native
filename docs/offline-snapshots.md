# Offline content snapshots

The app keeps the last content an account saw on each forum, so a launch shows
it before the first response and a launch with no network still has something
to read. Chat is not covered.

## What is kept

One owner-only JSON document per forum, in
`<application support>/content-snapshots/`, written through
`PrivateFileDocument`. It holds:

- the account it belongs to (`id:<n>`, `username:<name>` or `anonymous`);
- the first page of each topic list the account visited, with the path that
  loaded it;
- the opening window of the topics it opened last.

Each entry is the response body the site sent. Models have no encoder, and a
second description of the wire format would drift from the parsers, so a
snapshot is read back through `decodeTopicListWire` and `decodeTopicWire`, the
same projections a response goes through. `WireBody` carries the body beside
the model it produced; a model built by hand has none and is never saved.

Search results are not kept: they are answers to a question, not a place.

## Bounds

| Bound | Default |
| --- | --- |
| Lists per forum | 8 |
| Topics per forum | 12 |
| One response | 512 KiB |
| All responses of one forum | 3 MiB |

Measured on November 15, 2026 with `curl` against public forums: five first
pages of thirty topics were 37 to 79 KB, and the opening window of twelve
topics on Meta, the six longest and six shortest of its first page, was 18 to
142 KB. The entry bound is 3.6 times the largest of those. A response over it
is left out rather than truncated, because part of a response does not parse.
When the total is exceeded the oldest topics go first, then the oldest lists:
a list is what a launch shows before anything is tapped.

The file is larger than the total, because each body is stored as a JSON
string and is escaped.

## Reading

`TopicFeedController` asks for a list's snapshot only when the list has no
rows, alongside its request and never instead of it. A hydrated feed has
`TopicFeed.stale` set and `loading` still true. Rows go into the entity store
only where it holds no record, because any record already there came from a
request.

`TopicDataSession.open` asks once per topic and session, before the request,
when the store holds no detail for the topic. The restored topic counts as an
accepted read, so a custom reader resolves from it, and it is left marked
stale, so the open continues to the site as if nothing had been shown.

A response always wins:

- A list load holds a claim while its snapshot is being read. The response
  takes the claim as it commits, and a snapshot that arrives afterwards
  publishes nothing.
- A failed list request waits for the snapshot before it reports, so the error
  is drawn over the kept rows rather than replaced by them.
- A topic snapshot is dropped when a request for the topic began or published
  while the file was being read.

Every read and write checks the account's `SiteLease`. A read that outlives
its account answers nothing, and a response that outlives its account is not
written down.

## Writing

A save happens when a first page, or the window a topic was opened or
refreshed at, is published from the network. Paging and scrolling do not save.
Saves are applied in memory and committed together three seconds later, so a
burst of list refreshes is one write; saving a body identical to the kept one
writes nothing. Leaving the foreground and quitting commit at once. Documents
over 64 KiB are encoded and decoded on a worker isolate.

The first read of a forum happens when its first list loads, after the first
frame. Nothing is read in `AppBootstrap`.

## Deletion

`ShellController._forgetSiteState` deletes the forum's document. That covers
sign-out, an account change and the forum leaving the rail. The deletion runs
under the document's lock, behind any write already under way, and a save still
waiting on the delay is dropped.

A document written for another account, in another format version, or damaged
in any way is treated as absent and replaced by the next save.

## Not measured

The effect on cold-start milestones was not measured with
`tool/profile_startup.py`. Category names and colours are not kept, so a list
restored with no network shows its rows without category badges until the
site answers.
