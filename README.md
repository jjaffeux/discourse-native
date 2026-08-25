# discourse-native

An experimental native Discourse client, built with Flutter.

The optional-feature system is documented in
[Plugin architecture](docs/plugin-architecture.md), including full and
core-only build profiles.

Currently targets **iOS**, **macOS** and **Linux**. Android and Windows are
planned; see [Adding a platform](#adding-a-platform).

## Requirements

- Flutter 3.47.0 (the exact SDK used by CI and releases is pinned in `.fvmrc`)
- Xcode 26+ with the command line tools, for the iOS and macOS builds
- For the Linux build, on Debian or Ubuntu:

  ```sh
  sudo apt install clang cmake ninja-build pkg-config \
                   libgtk-3-dev liblzma-dev libstdc++-12-dev \
                   libwebkit2gtk-4.1-dev libsoup-3.0-dev
  ```

Run `flutter doctor` to check the toolchain.

## Running

```sh
flutter run -d macos                    # macOS desktop
flutter run -d <simulator-id>           # iOS simulator, see `flutter devices`
```

## Connecting a site

The `+` in the rail resolves whatever you type to a real Discourse. The lookup
mirrors DiscourseMobile's `Site.fromTerm` (`js/site.js` in that repo):

1. Bare hosts get `https://`. Explicit `http://` is accepted only for loopback
   development hosts; remote sites must use HTTPS.
2. `HEAD /user-api-key/new` — a 404 means it is not a Discourse, and the
   `Auth-Api-Version` header must be ≥ 2 or the site is too old for an app.
3. Redirects are followed by hand, because the URL we landed on is the one
   worth storing — `package:http` only reports the one originally requested.
4. `GET /site/basic-info.json` for the title, description and icon.

One deliberate difference: DiscourseMobile strips the port from the resolved
URL, which would make a site on `localhost:4200` unreachable. We keep it.

Sites are persisted with `shared_preferences`. This includes public site
metadata and, once connected, the account's public username, name and avatar so
the rail can render immediately after launch. Credentials never go there.

## Connecting an account

Tapping the user bar runs Discourse's **user API key** handshake, the same one
DiscourseMobile uses (`SiteManager.generateAuthURL` / `handleAuthPayload`):

1. A fresh 2048-bit RSA key pair is generated for the handshake. Generation
   runs in an isolate — it takes seconds — and the private half remains only in
   memory until the callback has been decrypted.
2. We open `{site}/user-api-key/new` in an `ASWebAuthenticationSession`, passing
   our public key, a random nonce, a client id and
   `auth_redirect=discourse://auth_redirect`.
3. The user signs in and authorizes. Discourse redirects to our scheme with a
   `payload` — the API key, RSA-encrypted to our public key.
4. We decrypt it and check the nonce matches the one we sent, which is what
   stops a reply from elsewhere being replayed at us.

Scopes requested: `read,write,session_info,notifications`. No `push` — there is
no push server.

Two things this depends on: `discourse` is registered as a URL scheme in both
Info.plists, and Discourse encrypts with Ruby's `public_encrypt`, i.e. **PKCS#1
v1.5**. `basic_utils`' `rsaDecrypt` uses raw unpadded RSA and will not work;
[user_api_key.dart](lib/src/data/user_api_key.dart) drives pointycastle's
`PKCS1Encoding` directly.

### Counters

Every number the shell shows — the rail badge and all the sidebar counts —
comes from a single call to `/notifications/totals.json`, not from a request per
section. It returns `unread_notifications`, `unread_personal_messages`,
`unseen_reviewables`, `chat_notifications`, `topic_tracking.{unread,new}` and
`username`. Key names are taken from what DiscourseMobile's `Site.refresh()`
actually reads.

The rail badge counts only things *addressed to you* (notifications, PMs, chat,
reviewables). Unread and new topics are sidebar counts, not rail badges —
otherwise a busy site would sit permanently at a four-digit number.

Refreshed on launch for every connected site, after connecting, and when
switching to a site. A failure is swallowed: counters are decoration and a site
being down must not break the shell.

Per-topic unread state does *not* need a separate call — `/latest.json` is
personalized when authenticated and each topic carries `unread_posts` and
`last_read_post_number`.

### Replies

The Replies tab is a second, server-filtered view of `/notifications.json`:
`recent=true`, a thirty-row limit, and the five types Discourse groups there —
`mentioned`, `group_mentioned`, `posted`, `quoted` and `replied`. It also sends
`silent=true`; opening one filtered category must not advance the account-wide
notification-seen marker the way opening the full Notifications tab does.

Replies and Notifications keep separate per-site feeds. Filtering the already
loaded Notifications rows in the client would filter *after* its thirty-row
budget and could hide older replies. A row present in both feeds is still one
notification, though: opening it marks it read in both cached lists (and in a
bookmark reminder, when it is there too) before the write returns.

### Chat notifications

When Chat is available to the connected account, its user-menu tab is another
independent, server-filtered notification feed. It asks for `chat_invitation`,
`chat_mention`, `chat_message`, `chat_quoted` and `chat_watched_thread`, again
with `recent=true`, a thirty-row limit and `silent=true`. The distinct per-site
cache keeps opening Chat from replacing Notifications or Replies, while marking
a shared notification read is reconciled across every cached feed.

The tab follows the same account-level gate as the rest of Chat: the totals
payload must expose `chat_notifications`, and an explicit
`has_chat_enabled: false` on the current user keeps it hidden. Notification
links preserve their exact message destination and open connected
channel/thread routes natively; disconnected or unclaimable destinations keep
the browser fallback.

### Bookmarks

The bookmarks tab reads `/u/{username}/user-menu-bookmarks.json`, which is the
menu's own route rather than the paged list behind the activity page. It answers
with **two** lists in one envelope: `notifications`, the bookmark reminders that
have fired and not been read, and `bookmarks`, filling whatever is left of a
twenty-row budget with the reminders' own bookmarks excluded so nothing appears
twice. Both are drawn in that order, the reminders through the same row as the
notifications tab uses — one of them read anywhere is marked read in both.

The route is the account's own and names it: Discourse raises `InvalidAccess`
for any other username, so signed out there is nothing to ask for.

Only the keys `UserBookmarkBaseSerializer` declares are read. Which serializer
answers depends on what was bookmarked — a post, a topic, a chat message, or a
plugin's own bookmarkable — and only the base's keys are common to all of them.
Navigation goes through `bookmarkable_url`, which every one of them builds, so a
bookmark on something this app has never heard of still opens.

Posts and topics also expose the complete core bookmark lifecycle. Their
personalized serializers populate one shared `Bookmark` record; post actions
and the topic header create, edit and delete through `/bookmarks`, while the
topic payload's `bookmarks` array drives the grouped list even for posts outside
the loaded stream. Notes, reminder presets/custom wall times and the four
auto-delete preferences match the web client. Reminder authoring prefers the
account's IANA timezone, then the device zone, then UTC; the process-wide
timezone database is shared with Local Dates.

Bookmark writes update the post, topic detail and cached list row together,
then force both a topic reconciliation and a user-menu bookmark refresh. Reads
capture a per-topic bookmark generation, so a response sent before the write
may refresh ordinary content but cannot put its older personalized bookmark
state over the confirmed result. An ambiguous create is never repeated: the
topic is read again because a timed-out first request may already have created
the one bookmark the target permits.

### Topic lists

`latest`, `new`, `unread`, `top` and `messages` all share one envelope
(`topic_list.topics` plus a `users` array), so they go through a single
`DiscourseApi.topicList(path:)`. `messages` is the exception only in that its
path is named after the account, so signed out it falls back to the placeholder.

Lists are cached per site and destination — revisiting one does not refetch.
Tapping the destination you are already looking at forces a refresh; merely
scrolling past the first row does not. It works signed out too, since
`/latest.json` is public; unread state simply arrives as zero.

Two things the payload makes you handle:

- Poster avatars live in a sibling `users` array keyed by id, and their
  `avatar_template` is usually site-relative with a `{size}` placeholder.
  `TopicList.fromJson` resolves them into each topic so widgets get plain URLs.
- Use `title`, **not** `fancy_title`. The latter is HTML — a title renders as
  `&ldquo;Regular mode&rdquo;` in a `Text` widget. `title` keeps ordinary text as
  plain unicode and emoji as `:shortcodes:`; [`TopicTitle`](lib/src/shell/topic_title.dart)
  resolves those shortcodes through the site's emoji set without asking an
  HTML renderer to interpret the rest of the title.

### Scrolling

The list is lazy already: `ListView.separated` with an `itemBuilder` is backed
by a `SliverChildBuilderDelegate`, so only rows near the viewport are built.
That is Flutter's virtualization — there is no separate widget for it. The
sidebar uses the same idea at destination-row granularity: its section shells
stay mounted so offscreen sections can restore stored collapse state without
building their rows, while each section's fixed-height
`SliverFixedExtentList` avoids building every destination upfront. The fixed
extent also gives Flutter the exact scroll boundary without measuring every
destination or estimating one independently updating section from another.

Pagination follows `topic_list.more_topics_url`, with one trap: Discourse
reports it as `/latest?no_definitions=true&page=1` — **no extension**, and that
route serves HTML. `TopicList.nextPagePath` inserts `.json` before the query.

The next page is requested from a scroll notification rather than from
`itemBuilder`, keeping the request off the hot path of building rows, and
starts a screenful early so rows are usually there before the user reaches
them. Topics already held are dropped by id when a page arrives: a topic
bumped between fetches shifts the window and comes back on the following page.

A scroll notification is **not** outside the frame, which is easy to assume and
wrong. A viewport whose scroll position ends up past the end of its content —
the window grew, the list shrank, a jump overshot — corrects that by starting a
scroll from inside its own `performLayout`, and the notification is dispatched
right there. So the load-more handler runs during layout, and the state change
it asks for would mark the tree dirty mid-frame:

```
Build scheduled during frame.
```

`ShellController._notify` is what makes that safe, by deferring a notification
raised during `SchedulerPhase.persistentCallbacks` to the end of the frame. It
is handled at that one funnel rather than at the thirty-odd call sites, none of
which can know which phase they are running in — `TopicView` reaches the same
handler the same way.

### Live updates

Everything on a Discourse that changes without being asked rides on
[message_bus](https://github.com/discourse/message_bus), and this client speaks
it through [dart-message-bus](https://github.com/jjaffeux/dart-message-bus) —
long polling, chunked streaming and the reference client's backoff schedule, in
pure Dart. It is a git dependency because it is not on pub.dev yet; the commit
is pinned by `pubspec.lock`.

One [`SiteTracker`](lib/src/data/site_tracker.dart) per site owns the
connection, and every channel rides the same poll — which is why it is one
object rather than one per feature. message_bus multiplexes; a second client
would mean a second connection held open for the same site.

| Channel                     | Carries                          | Drives                     |
| --------------------------- | -------------------------------- | -------------------------- |
| `/latest`, `/new`           | topics created and bumped        | the banner on a topic list |
| `/notification/{user}`      | every count for the account      | the dot on the avatar      |
| `/reviewable_counts/{user}` | what has appeared in the queue   | the same dot               |

#### New topics

The banner at the top of a topic list — *See 3 new or updated topics* — fetches
them and puts them on top when tapped. The shape is core's, from
`app/models/topic-tracking-state.js`:

| Channel   | Message type | Published when                | Counts for      |
| --------- | ------------ | ----------------------------- | --------------- |
| `/new`    | `new_topic`  | a topic is created            | `latest`, `new` |
| `/latest` | `latest`     | a post bumps an existing one  | `latest`        |

That split is why the two lists word it differently: only `latest` counts a
bump, and a bump is a topic *updated*, not a new one. `/new` is subscribed to
only when there is a key, as in core — a reader with no account has no "new".
Both start at `-1`, core's `messageBusDefaultNewMessageId`: what matters is
what has arrived since the list on screen was fetched.

[`IncomingTopics`](lib/src/models/incoming_topics.dart) is the counting half of
core's class and only that half. Core's also keeps a per-topic read/unread state
map feeding every badge in the app; a banner needs none of it. Two consequences
worth knowing:

- **Muted categories, tags and topics are not filtered out**, because that needs
  state we do not carry. A muted topic is counted and then does not come back
  when the list is fetched, so the banner can overstate by a row. It resolves
  itself — ids are cleared whether or not they produced a topic, so a banner
  that can never be satisfied cannot form.
- **Unread topics are not counted.** Core counts an `unread` message as incoming
  only when the topic's state says it was fully read before, which is exactly
  the state map that is missing.

Tapping asks the *list* route for those ids — `/latest.json?topic_ids=1,2` — the
same as core's `TopicList.loadBefore`, so each row arrives with its posters and
its unread counts rather than as a bare topic. Anything already held with those
ids is dropped before prepending, since a bumped topic is already somewhere
further down.

#### Counters

`/notification/{user_id}` is published by `User#publish_notifications_state`
every time anything about the account's notifications changes — an arrival, a
read, a dismissal. It keeps [`NotificationTotals`](lib/src/models/notification_totals.dart)
live, which is the one thing behind the rail badge, the user menu's tab counts
and the dot on the avatar that opens it. A dot rather than the number core's
header shows: the rail already carries the count for every site.

The arithmetic is the trap. The message carries its own `unread_notifications`,
and it is **not** the field `/notifications/totals.json` returns under that
name — `UserNotificationTotalSerializer` derives that one as
`all_unread_notifications_count - new_personal_messages_notifications_count`, so
private messages are counted once, under their own name. Reading the message's
field straight across makes the number jump the moment the first message
arrives and never agree with the endpoint again.

`/reviewable_counts/{user_id}` is a second channel for the review queue, and
only staff ever get one. `reviewable_count` is the size of the queue;
`unseen_reviewable_count` is what has appeared in it since the user last
looked, and that is the one anything here counts.

Two counts stay as they were, refreshed only by the totals call: chat, which is
published on a channel of its own, and the sidebar's unread and new topic
counts, which core derives from the per-topic state map this app does not keep.

The rows in the menu are not patched from the message either. Core splices the
`last_notification` it carries into its cached list and applies the read flags
in `recent`; here the tab refetches every time it is opened, so there is never
a stale list to reconcile — only a count, which is what the dot needs.

Both channels are named after the account, so they need its id — which meant
storing one. Sites connected before that get healed on the next launch: finding
a stored user without an id, `ShellController` asks `/session/current.json`
once and writes the answer back.

Three things about the connection:

- **One at a time.** A tracker is kept for every site visited, but only the one
  on screen is polling — the web only ever has one site, and a long poll per
  site in the rail is a held connection per site. Cursors survive being
  stopped, so returning to a site asks for what it published while it was away.
- **It is paced off the app lifecycle.** `DiscourseApp` maps `hidden`,
  `paused` and `detached` onto `ShellController.setForeground`, which is
  wired to the client's `shouldLongPoll` and `pollNow`. `inactive` is left
  out because it fires for the app switcher. Without it a backgrounded app
  holds a connection open that is usually dead by the time it comes back.
- **No new consent is involved.** `POST /message-bus/*/poll` is inside the
  `notifications` scope this app already asks for, which `RouteMatcher`
  special-cases since it is not a Rails route. The poll carries `User-Api-Key`
  and nothing else of `DiscourseApi.authHeaders` — that one sends `Dont-Chunk`,
  which would switch off the streaming this transport exists for.

Trackers are injectable (`ShellController.trackers`) for the same reason the API
client is: a widget test that builds a shell must not dial out, and the test
binding fails outright on the poll's backoff timer outliving the tree.

### Topics

Tapping a row pushes a topic route onto the content stack, so back returns to
the list — which is not refetched, since feeds are cached.

Topic-list rows carry `last_read_post_number` and `highest_post_number`. Like
Discourse's web client, an unread row opens at `last_read_post_number + 1`,
capped at the highest post; a fully read row opens at its last post. The
numbered `/t/{slug}/{id}/{post}.json` route returns a twenty-post window around
that position **plus the ids of every post in the topic**. The reader reveals
the requested post after the window is laid out, pages forward from the end of
that window, and offers earlier batches above it.

An unpositioned `/t/{slug}/{id}.json` request still returns the first twenty
posts. In both cases paging is by id (`/t/{id}/posts.json?post_ids[]=…`) rather
than by page number. Fetched posts are merged in post-number order, not append
order.

Post bodies are the `cooked` field — HTML the site already rendered, with its
markdown, oneboxes, mentions and emoji resolved. `flutter_widget_from_html_core`
draws it; reimplementing any of that client side would be a mistake.

Post, composer, grid, lightbox, onebox, and chat-upload images share one
site-image loader. That matters when a site enables secure uploads: Discourse
answers an anonymous `/secure-uploads/…` request with a 404 even though the
authenticated upload itself succeeded. The loader sends the user API identity
only to the forum origin, follows redirects explicitly, and never forwards
those headers to the signed object-store or CDN URL. Its encoded-byte cache is
memory-only and is discarded with the site's account lifecycle, so reconnecting
as another account cannot reuse private media from the previous session.

Two things worth knowing if you touch the lists:

- The load-more footer may only appear **while actually loading**. Keying it on
  "there is more" leaves a spinner running forever at the bottom.
- Fetching is triggered both from a scroll notification and from building the
  last row. The scroll alone is not enough: twenty short posts may not fill the
  window, leaving nothing to scroll and the rest never fetched.

`HtmlWidget` renders into a bare `RichText`, which `find.text` and
`find.textContaining` both ignore — widget tests need a `byWidgetPredicate`
finder to assert on post content.

### Composing

Discourse stores raw markdown, so the composer's field text **is** the payload.
There is no document model in between. That is a decision, not a gap: a rich
editor over markdown has to convert both ways, and the round trip is lossy for
anything it does not implement — an earlier `super_editor` composer had to
*refuse* rich mode for tables, lists and fenced blocks rather than silently
rewrite someone's post.

What replaced it is Discord's approach: don't convert the markdown, decorate it.
`MarkdownEditingController` overrides `buildTextSpan`, so `**bold**` draws faint
asterisks around a bold word while `controller.text` keeps every character. The
markers stay visible on purpose — hiding them is where an editor starts lying
about what will be posted.

One invariant carries the whole thing:

> the painted text equals `controller.text`, character for character.

Flutter neither asserts nor converts when those disagree. `RenderEditable`
computes caret positions, hit testing, word boundaries and select-all from the
flattened span tree (`plainText`) and hands the results straight back as offsets
into the field's string. So:

- **No `WidgetSpan` may stand in for more than one character.** A placeholder is
  worth exactly one `0xFFFC` code unit however wide it draws, so one replacing
  the seven characters of `:smile:` silently puts every later offset out by six.
  `markdown_highlight_test.dart` fuzzes 2000 inputs against the invariant, and
  `markdown_editing_controller_test.dart` round-trips the caret for it.
- **The composer field must never set `spellCheckConfiguration`.** `EditableText`
  routes around `controller.buildTextSpan` entirely once spell-check results
  arrive, so highlighting would vanish by flickering rather than by breaking.
  There is a test asserting it stays null.

`:smile:` draws the real artwork, and the way it does that is the interesting
part. The `WidgetSpan` stands in for exactly **one** character — the closing
colon — while the other six stay in the span tree as real text at `fontSize: 0`
and full transparency: six offsets, no pixels. Seven characters in, seven code
units out. Substitution only happens once the bytes are cached, so nothing
reflows under the caret mid-word and a name the site does not have 404s once and
stays text. Put the caret strictly inside and the characters come back to edit,
the way Obsidian's live preview does.

The scan runs on every text change, over the whole document, so what it costs
per character is a typing budget rather than a startup one. Four things keep
it linear, and all four are easy to lose:

- **Inline passes search one block at a time.** A block is a paragraph, minus
  any fence inside it — the two things a mark cannot span. Expressing that as a
  lookahead on every character a pattern consumes instead makes the scan
  quadratic: an opener with no closer after it walks to the end of the document
  before giving up, and the engine cannot know the next opener will fail for
  the same reason. `_blocks()` is where that rule lives, and `_pairs`,
  `_htmlTags` and `_inlineCode` are its three readers. It is a correctness
  rule before it is a speed one: a backtick left open at the end of a
  paragraph pairs with the next one anywhere below it, and the composer then
  draws a page of prose as code that the site is about to cook as bold,
  mentions and headings.
Emphasis is a ladder — `***`, `**`, `*`, then the underscore's `___`, `__`,
`_` — longest first, each pass closing what it took so the ones below skip it.
The underscore has the same rungs as the asterisk because Discourse reads it
the same way: `__bold__` is bold, not an italic `_bold_` with its underscores
showing. And a one-character delimiter still adjacent to its own character
after the ladder has run is a run nothing could use, so it is refused —
`a ** b ** c` is two runs of two, neither able to open or close for the spaces
against them, and taking one asterisk out of each italicised a sentence the
site leaves alone.

- **Emphasis is paired by scanning, not by a lazy pattern.** Even within one
  block the pattern re-walks it per opener, and a paste with no blank line in
  it is one block. The scan uses what the engine cannot: the closers after a
  later opener are a subset of the closers after an earlier one, so the first
  opener to run out of them is the last one worth trying.
- **Code spans are paired by walking the backtick runs.** The pattern this
  replaced had a lazy body and a backreference, and got two rules wrong on the
  way: it read a backslash-escaped backtick as a delimiter, though CommonMark's
  escapes work everywhere except *inside* a code span — so `` \` `` drew a
  whole sentence as code and closed it to every later pass, hiding the bold
  and the mentions the site really cooks. And the backreference could take the
  first backtick of a longer run as a closer, so `` `a`` `` became a code span
  the site leaves as text. A delimiter is a maximal run of unescaped
  backticks; `_backtickRuns` finds them in one pass and `_codeSpans` pairs
  them.
- **A link's closing bracket is found by `indexOf`, not by a pattern.** The
  same trap in the other bracket: a link's text class excludes `]`, so the
  closer can only be the first one on the line, and the engine consumed to the
  end of the line at every `[` and then handed the characters back one at a
  time looking for what that class had already ruled out. `_links` finds it
  directly, carries the line end forward instead of re-finding it per bracket,
  and remembers a line it has already shown holds no `]`.

A fourth rule is about the widgets the scan produces rather than the scan
itself. An image, a date, a poll and a quote each collapse into a
`WidgetSpan`, so their children come along with the span tree every keystroke
rebuilds — and the `GlobalKey` the controller holds for each one decides
whether that is a *rebuild* or a *recreation*. A recreation throws away the
element, its render objects and everything they had measured or memoised, so
minting fresh keys per text change meant paying for every projection in the
document on every key. `_retainPillKeys` keeps the ones whose projection is
unchanged, which on the ordinary path — typing at the end — is all of them.
Comparing the whole block rather than only its offset is the other half of the
rule: a following line can be appended at EOF before the next pointer-down but
before layout, and a key kept across that would hit-test what used to be
there. Measured per keystroke on a debug frame, twenty images in a document
went from 15.7ms to 5.9ms and six quoted posts from 17.2ms to 10.3ms.

The shape that finds this is a paste with no blank line in it — a stack trace
with a `_private` name per frame, a log line or a minified array with a bracket
per entry. Each of the three cost hundreds of milliseconds a keystroke.
`markdown_highlight_test.dart` times both shapes against their own eightfold to
keep the growth honest, since the cost is inside the regexp engine and cannot
be counted from outside.

A backslash before ASCII punctuation makes that character literal, and
`_escapes` records each `\x` in one pass — dimming the backslash, since
markdown-it consumes it and the post does not show it. What it *binds* is the
part worth knowing, because a backslash protects some of what this scan finds
and not all of it:

| Escaped                          | Because                                  |
| -------------------------------- | ---------------------------------------- |
| emphasis, links, code, inline HTML | markdown-it's own inline rules — the escape has consumed the character before they run |
| mentions, hashtags, emoji        | **not** escaped: these are Discourse's, added through `textPostProcess`, which `pretty-text/text-replace.js` runs over the text tokens of the *finished* inline pass — by which point `\@sam` is the text `@sam` and matches |

So `\*not italic\*` stops pairing and `\[text](url)` stops being a link,
while `\@sam` still draws its pill, because the site still draws that mention.
The pass runs after the code passes and only where the offsets are free, since
a backslash inside a fence or a code span is a backslash and the reader is
shown it.

Recording the offsets rather than checking afterwards is what makes the
emphasis case work: a pair that is found and then refused has already consumed
its closer, so `real *italic* after \*escaped\* one` would have lost the real
one. `markdownPairs` takes a `spokenFor` predicate and skips such a delimiter
instead — which also stops emphasis inside a code span eating the emphasis
after it.

The mention pattern is transcribed from core's own `mentionRegex`
(`frontend/pretty-text/addon/mentions.js`, snapshotted with the rest of the
hashtag markup), and its tail is the part worth knowing: a name may not *end*
in a dot, a dash or an underscore. `thanks @sam.` mentions `sam`. Reading the
period as part of the name asked the site about `sam.`, was told no, and drew
no pill on a mention the post really has — which is how most sentences that
end in one are written.

A shortcode needs a boundary before its opening colon, which is core's
`getEmojiName` rule and the reason `Standup at 10:30:45` holds no emoji called
`30`. It is switched off by an inline-emoji site setting, which is off by
default and is not a setting the scan can see — so the scan draws the default,
which is the side that cannot invent markup. `SiteEmojiText` is the other half
of that story and keeps its own answer: it draws prose the site has not cooked
and only draws names the site registers, which is a stronger filter than a
boundary.

`@`, `#` and `:` open a completion list. Trigger detection is pure
(`composer_triggers.dart`) and refuses more than it accepts — an email address
is not a mention, a lone colon is punctuation, a `#` inside a word is not a
hashtag, and a caret in the middle of a word is somebody reading rather than
composing. What the three kinds share and where they differ is under
[Mentions and hashtags](#mentions-and-hashtags); the short version is that a
hashtag completes to a *ref* rather than a slug, and refs contain colons, which
the walk has to be taught to cross. The list handles keys through a
plain `Focus` rather than a second `CallbackShortcuts`, which reports a key
handled whenever one of its activators matches, open or not — binding Escape
that way would close the composer instead of the list and throw away the reply.

### Likes

There is no `like_count` on a post. Likes arrive in `actions_summary`, the array
Discourse reports *every* post action in — the like is id 2 and the rest of that
table is flags. Missing keys are the ordinary case rather than a malformed
payload: `count` is dropped when it is zero, and `can_act`, `acted` and
`can_undo` are only written when they are true. The whole row is left out when
none of them apply, which is what your own post looks like, and what everyone's
looks like read signed out.

`can_act` and `can_undo` are never both set — liking spends one and grants the
other — so `Post.canToggleLike` picks whichever applies. A like can also be
neither: Discourse's undo window runs out, and the heart has to stop being
offered while the count still says the post was liked.

Writing goes through `/post_actions`, once each way: `POST` with the post id and
the type, `DELETE /post_actions/{id}` to take it back. Both answer with the post
itself, **unwrapped** — the controller serializes with `root: false`, so unlike
every other write here there is no envelope to look inside. Undoing can also
answer `204` when the post has stopped being visible to the reader, which is a
success with nothing to draw from.

The count is drawn before the request leaves and put back if the site refuses.
It is the one write here worth guessing at: a single tap people make while
reading, often several in a row, where a heart that waits for a round trip reads
as a broken button rather than a slow one. Nothing is lost if the guess is
wrong, which is what makes it safe — unlike a reply, where guessing would mean
showing a post that was never made. Discourse's own client does the same, in the
same order (`app/models/action-summary.js`).

One payload lies, and it is worth knowing which. `PostsController#update` — the
answer to an edit — serializes the post **without the reader's own post
actions**: no `topic_view`, no `post_actions`, unlike `render_post_json`. So
`actions_summary` comes back with no `acted`, and with a `can_act: true` that is
simply wrong on a post they have already liked. Taken literally it empties the
heart of anyone who fixes a typo, and the next tap earns an
`action_already_performed`. `Post.withLikesOf` is what stops that, and it is the
same thing `merge` does for `raw`: a copy that could not have known keeps what
it could not have known.

Who liked a post is a separate route, `/post_action_users`, asked for only when
someone opens the list — the stream carries how many, never which. It is capped
at 25 here; a much-liked post would otherwise answer with a couple of hundred
accounts for a popup that shows a handful, and the post's own count remains the
total so the difference can be named.

The count sits under the post rather than in the action menu, which is where the
reactions plugin puts its row of emoji. A like is that row with one entry in it,
and the entry is always a heart — see **Optional site features** below, which is
what replaces all of this on a site that has reactions.

### Optional site features

Discourse core is a floor, not a ceiling. A given site may have reactions,
solved, assign, chat, voting — or none of them, and the same rail can hold one
of each. The mechanism for that is
[`SitePlugin`](lib/src/plugins/site_plugin.dart), and it turns on one rule:

> **The record decides whether a feature is drawn. Site config decides only how
> to draw it, or what to offer inside it.**

`Plugin::Instance#add_to_serializer` defaults `respect_plugin_enabled: true`, so
a disabled plugin's attributes are simply *absent* from every payload. That
absence is the enablement signal, and it is a better one than any setting: it is
scoped by the same guardian that decided the rest of the payload, it can never
be stale relative to what is on screen, and it costs no request. So
`PostRecordPlugin.readPost` answering null means "this site did not mention
this", and everything keys off that — including which route a write goes down,
which is why the rule is worth stating rather than assuming. A gate that is
wrong for one frame produces a wrong *write*, not merely a missing button.

The other half is [`SiteConfig`](lib/src/models/site_config.dart), from
`GET /site/settings.json` — the only public payload carrying a plugin's own
configuration. `/site.json` does **not** have it: `SiteSerializer` is categories,
groups, archetypes and themes, with no `site_settings` key and no `plugins` key
at all. Config answers the question no record can — what may be *offered* that
has not happened yet, like a picker's emoji list — and nothing else. Every field
has a default, every default is core's own, so a site that will not answer is
drawn as core rather than drawn as broken; there is no loading state and no
error state because there is nothing worth telling a reader about.

It is fetched from `loadTopic`, **before** its early returns, and remembered on
the instance across launches. Before the guards, deliberately: both of them
return early on the ordinary path, so a fetch that only ran on a cache miss
would get one attempt per session with no way back if it failed. A count bounds
the retries instead. `_ensureCategories` answers the same question with the
other shape — its once-per-site guard is released again in its own failure
path, so the next thing that asks for categories retries. Signing out drops the
settings: on a `login_required` site they were only readable as that account.

Adding the next one is a module under `lib/src/plugins/<name>/` owning its
models, its state and its widgets, the narrow capability interfaces it actually
contributes, an entry in the `const sitePlugins` list, and its endpoints on
`DiscourseApi` beside everything else's. `PluginRegistry` owns ordered
fallthrough and additive dispatch, so a feature that only owns navigation does
not also carry no-op post, composer, and live-topic hooks. The API is the one
deliberate exception to the module owning its own code:
`FakeDiscourseApi implements DiscourseApi` is what turns a new call into a
compile error until the fake grows a knob for it, and that is worth more than
the tidier boundary.

### Reactions

`discourse-reactions` lets a site's readers give a post any of a set of emoji
instead of only a like. The two are the same thing underneath: one emoji is the
site's **main reaction** (`discourse_reactions_reaction_for_like`, `heart` by
default), and giving it writes an ordinary `PostAction` like. So on a site that
has this the like affordance is *replaced*, not joined —
[`PostFooter`](lib/src/shell/post_footer.dart) draws the row where the count
was, and the menu offers React where it offered Like.

**Nothing on a reactions post is ever written through `/post_actions`.**
Reacting with a non-excluded emoji creates a shadow like *alongside* the
reaction, so an unliking `DELETE` there destroys the like and orphans the
`ReactionUser` — a desync only a scheduled server job repairs. It also means
`actions_summary` is read here as a permission and never as a count:
`can_act` is the same `post_can_act?(post, :like)` the toggle route itself
checks, while `like_count` on that site is inflated by every shadow like, and
`acted` is true for anyone who reacted at all.

Three numbers, and only two of them add up:

- each pill's own `count`, which is what the row draws;
- `reaction_users_count`, distinct accounts who liked **or** reacted — *not*
  their sum, and provably larger, because a reaction whose emoji has since been
  deleted is dropped from the row and still counted here. It is never drawn;
- the reactor list's `total_rows`, which comes from the same query as its rows,
  so "and N others" adds up. That is what the panel counts with.

Writing is `PUT /discourse-reactions/posts/{id}/custom-reactions/{emoji}/toggle`
with no body, answering with the post unwrapped like the like routes. A true
toggle, so **not idempotent** — the same emoji twice removes it, a different one
replaces it — which is one more reason `_write` never retries. The row is drawn
before the request leaves, on the same bargain likes make. The answer's
*counts* are dropped, though: the plugin builds `reactions` one way for a topic
read (preloaded, raw SQL) and another for a write, and the second filters out
reactions whose emoji no longer exists, so merging it would bump a pill and
leave it wrong until the topic was read again. Only what the answer says about
this reader is taken.

A `404` means the plugin was switched off **or** the post is gone — the route
answers the same bytes for both — so it drops that one post's reactions and
nothing else. Emptying every footer in the topic because a moderator deleted one
post would be the wrong guess.

The main reaction is **not guessed**. `SiteConfig.mainReaction` is nullable, and
where it is unknown the React entry opens the picker instead of sending
`heart` — the setting is enum-constrained to what a site allows, and `heart` is
not even in the default enabled list, so a guess on a site whose admin chose
`+1` earns a 422 whose body says only "Sorry, an error has occurred." The menu
also labels from the reaction the reader *holds*, not from
`current_user_used_main_reaction`: someone who clapped has a shadow like, so the
naive label reads "Like this post" on a tap that would replace their clap.

A populated reaction row ends with the same smile affordance chat uses, so a
reader does not have to reopen the post menu to choose something else. It is
shown only while the post remains writable; an empty row still relies on the
menu because there is nothing under the post to attach it to. Ordinarily it
opens the site's configured reaction grid. When
`discourse_reactions_allow_any_emoji` is true it opens the full searchable site
emoji catalog instead — arbitrary emoji are never offered on a site whose
route would reject them. Reaction picks keep their own favorites history, as
the web client does, rather than displacing topic-composer emoji.

Live updates ride `/topic/{id}/reactions`, subscribed to only while that topic
is the one on screen. The message carries which emoji changed and no counts at
all, so it is an invalidation hint — the post is read again through
`/t/{id}/posts.json`, whose numbers agree with what the row was drawn from. A
write of this reader's own is skipped; its own answer is already on the way.

### Chat

`chat` gives a site channels and direct messages to read alongside its topics.
It is the first optional feature here that owns *navigation* and a *screen*
rather than decorating a record, so it contributes the sidebar and content
capabilities to [`PluginRegistry`](lib/src/plugins/site_plugin.dart) without
special-casing chat in the shell.

The native workflow covers followed channels, direct messages, search,
composing, uploads/GIFs, read state, live updates, and first-class message
threads. A thread can be opened from its latest-reply summary or created with a
message's Reply action. At 1200 logical pixels and above Chat owns a resizable
channel/thread workspace; narrower shells push the thread as the next screen.

**It cannot use the enablement rule the rest of that interface turns on.** A
post arrives whether or not you care about reactions, so its payload can be the
gate. A channel list arrives only if you ask, so its absence proves nothing — a
site without chat and a site nobody asked look exactly alike. The nearest thing
to the rule is `chat_notifications` on `/notifications/totals.json`, which this
app already fetches for every connected site on launch. It is serialized only
when `SiteSetting.chat_enabled && scope.can_chat? && user_option.chat_enabled`:
three questions answered by one absent key, scoped by the same guardian that
decided the rest of the payload. So **it decides only whether to ask; the answer
still decides whether to draw.** Nothing is drawn from a setting — the sections
exist because there are channels. `SiteConfig` is deliberately not used even
though `chat_enabled` is a client setting: it arrives late, it can be refused,
and it is not scoped to this reader's own preference, so it would put a Chat
heading in front of someone who turned chat off.

There is no loading state and no empty heading, for the reason `SiteConfig` has
neither: a heading that appears and then vanishes is worse than one that arrives
late, and a section with a spinner in it says something untrue about how many
channels there are.

Search is the deliberate exception to the final presentation rule above. The
separate, headerless Search row and the channel-header action require all of the
account-level Chat gate **and** an explicit `chat_search_enabled: true` from
`/site/settings.json`; a missing setting means an older server whose search
route must not be probed. Global search calls `GET /chat/api/search.json` in
20-message pages, defaults to relevance, can switch to latest, and includes
thread replies. Each result keeps the embedded channel only as presentation
context. Opening one resolves `/chat/api/channels/{id}.json` when that channel
fell outside the capped followed-channel snapshot, stores the full membership
record, then targets the exact channel or thread message.

The inline channel filter uses the same endpoint with `channel_id`,
`sort=latest`, and `exclude_threads=true`. It automatically reveals the newest
match, cycles through the returned window in both directions, and reuses the
one-shot navigation handoff so an expanded thread workspace can reveal a
message in its parent pane without closing the thread. Search state lives in a
separate lifecycle-safe controller: query changes, site disconnects, and a
closed filter invalidate late responses, while search text remains transient
and never enters diagnostics or persisted presentation state.

The two hooks are `sidebarSections` and `content`. The first returns **models**
rather than a widget — unlike `postFooter`, because the sidebar is a list of
peers rather than a canvas, and a row a plugin drew itself would drift from
core's the first time either changed. The second is the ordered fallthrough
`postFooter` is, asked before core, matching on `ContentRoute.id` — which
`ContentRoute.fromDestination` copies straight from the destination chat minted,
so a feature recognises its own routes by the ids it wrote. Nothing about chat
is written into `ContentRoute`, and none of `_feedPath`, `sidebarBadgeFor` or
`IncomingTopics` needed an arm; that they did not is the best evidence the seam
is in the right place.

**Titles come from the site.** `title` is `name || title(scope.user)`, so a
group direct message's "hawk, kris and 3 others" has already excluded the
reader, sorted the rest by the site's naming rules and truncated past seven.
`unicode_title` is that same text with `:tada:` turned into 🎉, which is what a
`Text` can draw — the argument `jsonTitle` already makes for plain over fancy.

Unread counts arrive in a sibling map, `tracking.channel_tracking`, **keyed by a
string** — it is a Ruby hash keyed by integer and JSON object keys are strings,
so channel 9 is looked up as `'9'`; reading it as an int finds nothing and
reports "all read". They are folded onto the channel record at parse time so a
sidebar row watches one thing. The row draws a **dot**, not a number, which is
what Discourse draws: the count in a busy channel moves faster than it is worth
reading. Red for anything addressed to the reader — a mention, or any unread
message in a direct channel, which is addressed to them by construction — and
the quieter colour for an unread public channel they merely follow. A muted
channel says nothing at all, which is what muting means.

**Channel and thread timelines are separate state.** `ChatStreamTarget` is
either a channel or a `(channel, thread)` pair, and the site plus that target
keys the message window, pagination, optimistic FIFO queue, composer, read
receipt and MessageBus subscription. A reply carrying `thread_id` is accepted
only by its thread stream; it can update the original message's summary but can
never enter the channel's message ids.

Both directions page with explicit 50-message windows. A normal open anchors at
the server-selected last-read message; a summary targets its `last_reply_id`,
and a native notification or `/chat/c/-/...` link targets the exact message.
Older and newer pages use the oldest/newest persisted id and preserve viewport
position. The stream remains contiguous: a live reply beyond an historical
window is deduplicated into a pending count and “Jump to latest” replaces that
window with the live edge instead of creating an unfillable hole.

Read state follows the same boundary. After a persisted message stays visible
for 500 ms, the viewport advances a monotonic receipt for its own target. A
channel read never reads thread replies, a thread without
`current_user_membership` draws no unread divider and sends no receipt, and a
channel pane hidden by compact thread navigation cannot read anything. Creating
membership by replying or changing the thread notification level enables the
thread path after detail reconciliation.

The stream is one flat list, oldest first, **contiguous** — that is the
invariant paging depends on, since `loadOlder` pages before the first message
held and a hole above it could never be filled. So a re-open *replaces* rather
than merges. Ids in each response are deduped and sorted by `(created_at, id)`,
the site's own `ORDER BY`; a directional page is then joined at the edge its
cursor contract names instead of re-reading and sorting the whole accumulated
history. The tiebreak is load-bearing rather than tidy, because iso8601 carries
seconds and Dart's sort is unstable, so two messages written in the same second
would otherwise swap places and reshuffle the list under the reader. A page
that arrives with no new ids in it also ends the paging, whatever the site said,
so a cursor answering the same page forever cannot spin.

**The list is reversed, not the array.** Index 0 is the newest message. Older
messages take higher scroll offsets, the viewport lays out from offset 0 outward
and holds `pixels` across a change in content extent, so a page of history
landing at the far end moves nothing the reader is looking at — no offset
correction, no sliver split. Rendering forwards and inserting at index 0 would
throw them into the past on every page. The consequence to keep in mind is that
`extentAfter`, which in a topic means "further down, later", here means "further
up, **earlier**". The app's existing two-pronged load-more turns out to be
exactly Discourse's two rules already written down: the scroll threshold is its
load-at-top, and building the last row is its fill-pane safety net.

Messages group into runs the way Discourse's do — same author, within five
minutes, previous not deleted, neither a webhook message, and a reply only when
it answers the row directly above. One rule of Discourse's is dropped: it also
breaks the chain at the first message of the latest fetched page, because its
stream is assembled from pages whose adjacency it cannot vouch for. Here
contiguity is an invariant, so a page boundary carries no information and
honouring it would put a seam in a conversation whose only cause is how the
bytes arrived. A day separator sits above each calendar day, in the reader's
days rather than the site's; a run of deleted messages — which only a moderator
is ever sent — collapses into one row.

**Uploads are not in `cooked`.** `Chat::Message#cook` cooks the raw `message`
and not `to_markdown`, so unlike a post, where Discourse bakes images into the
HTML with the lightbox markup around them, a chat message's attachments are only
ever in the `uploads` array and have to be drawn from it. Images go through the
same viewer a post's do — `LightboxImage` is a plain value object and
`LightboxGallery` takes a list of them, so nothing about the cooked-HTML path is
in the way. Everything else is a row with a filename and a size.

Reactions are drawn and their incremental live events update the held message.
Once a message has a reaction, its row ends with the web client's outlined
smile button and opens the full site emoji picker in the chat favorites
context. A picker choice is an explicit add, not the toggle an existing pill
performs, so choosing an emoji the reader already holds leaves it in place.
The picker and additions remain unavailable when the message is not persisted
or its channel is unfollowed, silenced, archived, or otherwise unwritable. An
already-held reaction may still be removed after leaving an otherwise writable
channel, matching the server's undo rule. A threaded root draws one accessible
latest-reply card — author, time, excerpt, total replies and
representative participants — which opens at the latest reply. The complete
root also appears inside the thread, where that card is suppressed to avoid
recursive navigation. Reply actions use hover/context-menu and keyboard access
on desktop and a long-press sheet on touch platforms.

Sidebar activity follows each channel's `/chat/{id}/new-messages` stream from
the cursor captured with the channel-list response. That updates last-message
and immediate unread state in the same turn, and the direct-message section
uses the web client's urgent/thread/activity ordering rather than blindly
moving an event to the front. `/chat/new-channel` brings in conversations first
followed on another client, while the single and bulk user-tracking streams
reconcile reads and counts from the account's other sessions. A mounted channel
or thread also reference-counts `/chat/{id}` from the cursor in the same HTTP
snapshot; an active thread additionally follows
`/chat/{id}/thread/{thread_id}` from its detail cursor. Sent, processed, edit,
refresh, reaction, delete, bulk-delete and restore events are deduplicated
across replay/reconnect. `update_thread_original_message` is authoritative for
reply count, latest reply and participants; the active detail is coalesced and
refetched because core's event does not carry cross-client title changes.

Chat routes persist only stable channel/thread identity. Exact message anchors
and composer-focus requests are one-shot destinations, so selecting another
message in an already-open thread reveals it without stacking duplicate routes.
Connected-site channel and thread links from notifications, bookmarks and
internal navigation are offered to native Chat before browser fallback.
Thread notification settings expose core's Normal, Tracking and Watching
levels; Muted, thread lists, “My Threads” and title editing remain out of scope.

### GIFs

Core's GIF picker is an authored remote image, not an upload and not a native
provider integration. On Discourse `v2026.7.0` and newer the app reads
`enable_gifs` and the Klipy presentation limits from `/site/settings.json`, then
uses the connected account's user API key for `GET /gifs/categories.json` and
`GET /gifs/search.json`. Discourse proxies those requests, so the Klipy API key
never leaves the server and this client never talks to Klipy directly.

The picker shares categories, debounced search, cursor paging, result limits and
Klipy attribution across composer surfaces. A topic selection is inserted as
the same `![title|widthxheight](url)` block the web composer writes. Chat keeps
its compact composer: a selection is staged as its own optimistic message, and
an unchanged draft is cleared only after the send succeeds. A failed send or a
draft edited while it is in flight is retained.

The older `discourse-gifs` theme component is deliberately unsupported. It has
no authenticated server route or reliable capability contract and would require
a native client to discover theme settings and contact a provider with its
credentials.

### Emoji

Post bodies carry emoji as `<img class="emoji" src="/images/emoji/…">`, and they
did not render at all until
[`emojiWidgetBuilder`](lib/src/shell/emoji.dart) existed: `HtmlWidget` has no
base URL to resolve a root-relative `src` against, so `TagImg` fell back to the
`alt` attribute and every emoji in every post read as the literal text
`:slight_smile:`.

Setting `HtmlWidget.baseUrl` would have fixed the URL in one line and routed
*every* `<img>` in every post through `NetworkImage` — unbounded concurrency, no
failure caching, one request per glyph. That is the exact 429 story
`AvatarLoader` exists to prevent, so emoji go through a sibling of it,
[`EmojiCache`](lib/src/data/emoji_cache.dart), and the caching and concurrency
cap they share live in [`ByteCache`](lib/src/data/byte_cache.dart).

Reactions need the other direction — a name, not a `src` — which is
`SiteConfig.emojiUrl`, mirroring `Emoji.url_for`: `{external_emoji_url or
site}/images/emoji/{emoji_set}/{name}.png`, with a `:tN` tone suffix becoming a
`/N` path segment. The `?v=` core appends is a build constant with no JSON
endpoint to read it from; it busts caches and nothing else, and `EmojiCache` is
the cache here. Custom emoji are the exception: they are uploads, and 404 at
that address, so the controller consults the site's own map of them
(`/site/emoji.json`, fetched beside the settings) before falling back
to it.

Titles, chat previews and search results are the third case: no cooked HTML,
just prose that may contain `:shortcode:`. `SiteEmojiText` draws those, and
draws only the names the site actually registers — the pattern for a shortcode
also matches ordinary punctuation, so "Standup at 10:30:45" contains `:30:`,
and an optimistic reader gave it a blank box sized to the text while it
fetched artwork that cannot exist, reflowed once on the 404, and settled back
to the text it started as. `SitePresentationController.knowsEmoji` answers
from the custom-upload map and the emoji catalog; `emojiUrl` deliberately
still answers for any name, because the standard-set address is computable
and that is exactly why it cannot decide this. The catalog is warmed when a
site is selected, since otherwise every title holding emoji would spend a
frame as its own raw shortcodes.

### Links

Every tapped link — in a post, a quote attribution, a onebox card — goes through
[`openLink`](lib/src/shell/open_link.dart), which decides where it belongs:

| Link                                     | Opens                          |
| ---------------------------------------- | ------------------------------ |
| `/t/{slug}/{id}` on the site being read   | here, as a topic route         |
| a topic on another site in the rail       | that site, then the topic      |
| `/u/{username}` on the site being read    | that person's card             |
| `/c/{slug…}/{id}` — a category            | here, as a filtered topic list |
| `/tag/{slug}/{id}` — a tag                | the same                       |
| anything else                             | the platform browser           |

Two things make this work. Discourse writes its internal links site-relative, so
they are resolved against the current site before anything looks at them
(`ShellController.absoluteUrl`). And sites are matched by **host and port, not
scheme** (`DiscourseInstance.serves`) — a post from 2013 linking to `http://`
still points at the same forum, while two development forums on localhost differ
only by their port.

A link only knows the slug, so a topic opened from one is titled from the slug
until the real title arrives with the topic and replaces it.

The two list routes are the only ones that carry their own feed path
([`ContentRoute.feedPath`](lib/src/models/content_route.dart)). Every other
destination is one the sidebar already knows the address of; a category exists
here only because a post mentioned it, so the route brings the address with it
and `_feedPath` looks in the content stack before its own table. The path is the
href with `.json` appended and is never rebuilt from the slug and the id — a
category's slug path is arbitrarily deep, and a tag with no slug is written
`/tag/12-tag/12`. Only the *unfiltered* list is claimed: `/c/x/5/l/top` is a
filter with no screen here, and showing the unfiltered list instead would be
answering a different question.

### Mentions and hashtags

Discourse draws `@sam`, `#support` and `#bug` as **pills** — a rounded tinted
chip with the name in it, and for a category a coloured square beside it. All
three share one SCSS mixin upstream, which is as clear a statement as the
stylesheet can make that they are one idea; [`Pill`](lib/src/shell/pill.dart) is
the same statement here, and every measurement in it is a ratio of the
surrounding prose for the reason `emojiScale` gives.

A pill is a widget rather than a style, and that costs something worth writing
down: claiming an element in `customWidgetBuilder` means `HtmlWidget` never
walks its children, never runs `customStylesBuilder` over it, and never fires
`onTapUrl` for it. So the pill draws its own label and carries its own tap. It
also means `find.text` sees the pill's label while the paragraph it sits in has
only the `￼` a `WidgetSpan` flattens to — `cooked_html_test.dart` has a
`paragraphOf` helper beside `renderedText` because the two now answer different
questions.

Two things about the cooked markup are worth knowing before reading
[`hashtag.dart`](lib/src/shell/hashtag.dart), because both look like bugs
otherwise:

- **The `<svg>` inside a hashtag is a placeholder.** Every one Discourse cooks
  carries the same `d-icon-square-full`, whatever the hashtag is; its own client
  throws that away and redraws from `data-type`, `data-style-type`, `data-icon`
  and `data-emoji`. Reading it would put a filled square on every tag on the
  site. The attributes are read and the svg is ignored.
- **The colour is not in the markup at all.** On the web it arrives in a
  generated stylesheet. Here the read path already has it: `data-id` *is* the
  category id, and categories are fetched once per site and read back by id. So
  a cooked hashtag costs no request. The composer cannot do that — it has a
  *ref* (`parent:child`, `name::tag`), the identity store is keyed by id and
  cannot be enumerated — so it asks `/hashtags.json`. Two keys, two sources; the
  asymmetry is the design, not an oversight.

The initial `/categories.json` read paginates to twenty parents on a large or
lazy-loading site, so some hashtags can draw a neutral square with the right
name and a working tap. Opening **All categories** loads the remaining pages as
the grid scrolls and fills those identities in. Before then, the neutral square
is what Discourse itself shows while its own category data is still absent.

Not everything gets a pill, and that is deliberate. An unresolved mention cooks
as `<span class="mention">` and an unresolved hashtag as
`<span class="hashtag-raw">`; Discourse leaves both as plain text, and so does
this. A pill over `@nobody` would promise a person who is not there. Group
mentions do get one — they are real links — but no glyph, because a glyph would
be encoding *this app's* lack of a group screen rather than anything about the
post.

**In the composer** the same pills are drawn over the text being typed, which is
the emoji trick from
[`markdown_editing_controller.dart`](lib/src/shell/markdown_editing_controller.dart)
applied twice more: the run's last character becomes a `WidgetSpan` and the rest
stay as real text at `fontSize: 0` and full transparency, so *n* characters in
is still *n* code units out and every later caret offset still means what it
says. Three details fall out of that:

- **The reveal rule differs by kind, and has to.** A `:smile:` run only exists
  once it is closed, so revealing it *strictly* inside is right — a caret at
  either end must not, or typing the final colon would never show the picture.
  A mention or a hashtag has no closing character: the run grows under the caret
  as it is typed, so the caret is always at its end. Strictly-inside would
  substitute a chip mid-word *and* ask the site about every prefix along the
  way. Adjacency is what keeps `#ran` as text until the space that finishes it —
  and what makes the lookups batch, one request per paragraph rather than one
  per keystroke.
- **The composer asks before it draws.** `@nobody` and `#TODO` cook as plain
  text, so a pill over either would be the field claiming something the post
  will not do — the exact failure the document-model composer was removed for.
  Names go through `/composer/mentions` and refs through `/hashtags.json`, each
  asked once and remembered, including the noes. Accepting a suggestion costs
  nothing at all: the search already said what it was, and the answer is kept.
- **The composer pill shows the characters that are in the field.** The cooked
  pill shows the site's own `Parent > Child`; the composer shows `#parent:child`,
  because what is drawn there has to be what will be posted. This is the thing
  in the feature most likely to be "fixed" by a later reader.

`#` completes like `@` and `:` do, with one wrinkle. The autocomplete inserts a
**ref** and never a slug — `parent:child`, `name::tag` — since that is the only
form that survives a subcategory or two things sharing a name. Refs contain
colons, and the backward walk in
[`composer_triggers.dart`](lib/src/shell/composer_triggers.dart) stops at one,
which left `#parent:child` looking like an emoji called `child`. So when a colon
stops the walk it keeps going, over colons as well as names, and if a `#` opens
the whole run it was a hashtag all along. Only in that direction: an emoji name
may not contain a colon, so nothing a `#` starts can be mistaken for one and
`:smile:` is untouched.

### Oneboxes

Oneboxes are the exception to "let `HtmlWidget` draw the cooked HTML". Discourse
styles them entirely from a stylesheet, and `flutter_widget_from_html_core` has
no stylesheet engine — it reads only the `style` *attribute* of individual
elements, and treats a `<style>` tag as non-rendering. So none of Discourse's
`onebox.scss` can be reused here, at any price, and an untouched onebox arrives
as an unstyled pile of text and images.

[`oneboxes/`](lib/src/shell/oneboxes/) draws them natively instead. One file
per onebox, laid out by what the onebox is:

```
oneboxes/
  onebox.dart                  the envelope, the generic card, the dispatch
  inline.dart                  a.inline-onebox stays text; PR glyph injection
  github/
    github.dart                octicons, status colors, shared body parts
    pr/block.dart              aside.onebox.githubpullrequest
    pr/inline.dart             an inline PR link, with its status glyph
    issue/block.dart           aside.onebox.githubissue
    commit/block.dart          aside.onebox.githubcommit
  discourse/
    topic/block.dart           aside.onebox.discoursetopic, a topic elsewhere
    user/block.dart            a profile on the site the post was written on
    category/block.dart        a category on the site the post was written on
```

Not every onebox gets a file — there are dozens of engines and they churn.
[`onebox.dart`](lib/src/shell/oneboxes/onebox.dart) reads the envelope every
engine shares, which is `_layout.mustache` upstream, and whatever no engine
claims is handed back to `HtmlWidget` inside the native card:

| Markup                    | Drawn as                                    |
| ------------------------- | ------------------------------------------- |
| `aside.onebox`            | the card, tappable to `data-onebox-src`     |
| `header` → `img.site-icon`, `a` | favicon + site name row               |
| `article.onebox-body` → `img.thumbnail` | lead image, left of the text  |
| … → `h3`/`h4`             | title                                       |
| everything else           | handed back to `HtmlWidget`                 |

That last row is what keeps unknown and future engines working: whatever the
parser has no opinion about still reaches the reader, inside native chrome.
`img.onebox-avatar` is the one engine-specific signal the generic card honours
— Twitter and friends lead with an avatar, which reads wrong as a rectangular
thumbnail.

The GitHub engines draw their bodies the way the web's stylesheet arranges
them — icon column beside the title, the facts, then the body underneath —
with the octicons taken from Discourse's templates and the `--gh-status-*`
colors of `github-pr-status.scss` for pull requests. The internal engines draw
the oneboxes Discourse writes for links to itself: a topic on another site,
and a same-site profile or category. A same-site *topic* link arrives as an
`aside.quote` — Discourse renders it as a quote of the first post — so it is
`quote.dart`'s, not an onebox engine.

Inline oneboxes are the other shape: a link that did not sit alone on its line
keeps its anchor and gets its title fetched instead —
`<a class="inline-onebox">`. The title remains ordinary anchor text so it can
share a line with the prose around it and wrap at word boundaries. A custom
widget factory injects the pull request's status glyph ahead of that text.

The parsers never mutate the DOM they are handed; a body remainder is
serialized back to a string. The document belongs to the caller's `HtmlWidget`.

The remainder goes back through [`CookedHtml`](lib/src/shell/cooked_html.dart),
not through a bare `HtmlWidget`, so an onebox containing a code block gets the
same code block a post does. That matters for git blob oneboxes — see below.

### Code blocks

`<pre>` is drawn natively too, by
[`code_block.dart`](lib/src/shell/code_block.dart). `HtmlWidget` handles a plain
`<pre>` fine; what it cannot handle is something *structural* nested inside one.
Git blob oneboxes put a numbered list in there:

```html
<pre class="onebox"><code class="lang-rb">
  <ol class="start lines" start="78">
    <li>def self.get_from_url(url)</li>
```

Rendered as HTML that becomes list items separated by every newline the mustache
template indents with — a wall of double-spaced, numbered lines. `CodeBlockData`
reads both shapes: an `<ol class="lines">` becomes numbered lines starting at
`start`, anything else is the text of the `<code>` split on newlines.

Lines scroll horizontally rather than wrapping, because wrapping makes
indentation lie about structure. `<li class="selected">` — the lines the link
pointed at, e.g. `#L78-L94` — keeps its highlight.

Rendered code, inline `<code>`, `<kbd>`, and their composer previews all use the
bundled regular and bold weights of JetBrains Mono. That is the web client's
`--d-font-family--monospace` face; its `Consolas, Monaco, monospace` fallback
stack and disabled ligatures are kept here too.

#### Syntax highlighting

Discourse highlights code in the browser, not in `cooked`, so the HTML arrives
as raw text and the tokenizing has to happen here.
[`syntax.dart`](lib/src/shell/syntax.dart) runs `package:highlight`, the Dart
port of highlight.js — which means it already understands the language names
Discourse writes, including aliases like `rb`.

Three things that are not obvious:

- **Highlighters tokenize a document; we draw lines.** A block comment or a
  heredoc is *one* token spanning several lines, so the token stream is cut back
  up on newlines. Line numbers and selection come from the markup and are
  carried across, never recomputed from the highlighter's output.
- **`lang-plaintext` is Discourse's default, not a missing value.** It means the
  author didn't name a language, so it is left unhighlighted rather than
  auto-detected. Only `lang-auto` (the pastebin onebox) detects, and against a
  short candidate list — real hljs auto-detection parses with all ~190
  registered languages.
- **Nothing is allowed to fail loudly.** An unknown language parses as
  plaintext, a highlighter exception falls back to plain text, and a block over
  `maxHighlightedChars` is not highlighted at all — a post rebuilds every time
  it scrolls back into view, and colour is worth less than a smooth scroll.

Colours are a `CodeColors` theme extension, tuned per brightness. highlight.js
emits around forty scope names; `scopeColor` groups them into six so a block
reads as code rather than as confetti, and so an unanticipated language still
lands somewhere sensible.

Since this depends on markup no one versions or announces,
`tool/markup_contract.dart` diffs the upstream templates, SCSS and JavaScript
against the snapshots under `tool/`:

```sh
dart run tool/markup_contract.dart             # fails if upstream moved
dart run tool/markup_contract.dart --update    # accept, then read the diff
```

It is a drift detector, not a source of styling — the SCSS is snapshotted
because it is where the class names the parser matches on are given meaning.

The three snapshots cover oneboxes, mention and hashtag markup, and the poll
skeleton and web-client handoff. Each names what to re-read when it drifts,
because "check whether the onebox parsers still handle it" is wrong advice for
a hashtag or a poll. A path that has *moved* fails harder than one that changed
— upstream put the JS under `frontend/` at some point, and a check that quietly
reported no drift because it could not find the file would be worse than no
check.

### Avatars

Avatars go through [`AvatarLoader`](lib/src/data/avatar_loader.dart) rather than
`NetworkImage`, for two reasons that only show up against a real site:

- **Format is not knowable from the URL.** Discourse serves some avatars as
  `image/svg+xml` from a URL ending in `.png`, and `dart:ui` cannot decode SVG.
  The loader reads the content type, falls back to sniffing the leading bytes,
  and `AvatarImage` renders with `SvgPicture.memory` or `Image.memory`.
- **A first render asks for ~90 avatars at once** (three posters × thirty
  topics) and earns an HTTP 429. The loader caps concurrency and caches by URL
  — *including failures*, so a rate-limited avatar is not retried on every
  rebuild, which is what turned one 429 into a stream of them.

Anything undecodable falls back to a placeholder rather than throwing.

Categories are fetched once per site from
`/categories.json?include_subcategories=true&include_topics=true` and flattened,
because topic rows look categories up by id and subcategories arrive nested.
The embedded featured-topic summaries power the native **All categories** card
grid without a second first-page request; later category pages are fetched only
as that grid scrolls.

### Disconnecting revokes

`POST /user-api-key/revoke` runs before the local key is deleted, on both
disconnect and removing a site. Deleting only our copy would leave a live key in
the user's authorized-apps list with nothing tying it back to us. A 404 is
tolerated — older sites lack the route — and so is being offline; the key is
forgotten locally either way, since keeping one we can no longer see is worse.

### macOS keychain

Apple API keys use the Data Protection Keychain under the namespaced service
`org.discourse.native.credentials`. A TestFlight/App Store signature supplies
the app's private application-identifier access group; the plugin does not
request a shared group, so no Keychain Sharing entitlement is needed. Without
that signed application identifier, Data Protection operations fail with
`errSecMissingEntitlement` (-34018).

Older builds used the legacy login keychain and the generic service
`flutter_secure_storage_service`. That keychain binds a separate ACL to every
item, so changing from the old development certificate to TestFlight could
produce one password prompt per connected site even though both apps were
signed. Release builds recover those credentials lazily by exact key: read the
new service first, read only the matching legacy item when absent, durably write
the Data Protection copy, then mark that namespace authoritative. Migration
does not delete ACL-protected old items: plain **Allow** must not cause a second
password prompt. Those inert items can be removed later in Keychain Access. The
migrator never calls `readAll`. macOS may still require one final authorization
for an old item because a newly signed identity cannot silently claim another
code requirement's secret.

Custom-signed macOS debug and profile builds use bundle id
`org.discourse.native.dev` and the isolated login-keychain service
`org.discourse.native.dev.credentials`; release keeps
`org.discourse.native`/`org.discourse.native.credentials`. Development builds
therefore need no provisioning profile and cannot prompt for, migrate, or
delete production's old login-keychain items. Only a distribution-signed
release has the application identifier required by its Data Protection
backend; a locally custom-signed release is not a runnable credential-storage
configuration. Migration operations are serialized in-process and across app
processes with an owner-only advisory lock, taken without blocking and
retried from the event loop: a blocking `flock` stops the whole isolate, and
the operations behind this lock can wait on a human. The legacy read is made
outside it for that reason — it is what may raise the ACL dialog — and the
modern namespace is re-read under the lock before anything is copied, so a
migration or disconnect from another process in that window is not undone. A
Data Protection state item is made authoritative before deletion cleanup, so a
legacy ACL refusal cannot keep a key active or resurrect it; reconnecting
makes the replacement durable before lifting that tombstone.

`integration_test/keychain_test.dart` covers missing-item behavior and a real
round trip. Unit tests verify the modern/legacy native options, migration
ordering, failures, and read/write/delete races.

On Apple, API keys live in Keychain keyed by site URL. The client id, username
and avatar are not secrets and live in preferences, so a relaunch knows who you
are without a round trip. A client id left in Keychain by an older build is
copied to preferences after the first successful preference write; its old copy
is then inert and is not touched again.

Unsent local draft mirrors no longer share the Apple Keychain service. They use
an owner-only, atomically replaced file at
`Application Support/drafts/drafts-v1.json`; Linux retains the existing private
XDG JSON store. Complete-file updates share an in-process queue and an advisory
sidecar lock, so separate persistence instances or processes cannot overwrite
one another's snapshots. That transaction protocol has one owner in
`foundation/private_file_document.dart`; each store still owns its schema and
migration policy. An Apple release can recover an old Keychain draft
only when that exact draft is opened; the old copy is left inert to avoid a
second ACL prompt. Durable key and site-prefix blockers prevent a cleared draft
from later being resurrected, account-boundary clearing fails if its blocker
cannot be written, and no draft operation enumerates Keychain. Still-older
preference drafts are moved only after the private file write succeeds.

## Checks

```sh
dart format --output=none --set-exit-if-changed lib test integration_test tool
flutter analyze
flutter test
```

`flutter analyze` runs `flutter_lints` plus the rules in
`analysis_options.yaml`, which are there to catch a class of mistake rather
than to enforce a style: an unclosed subscription or sink, a `Future` nobody
waits for, a `dynamic` call, an equality or `contains` between unrelated types,
a `hashCode` that disagrees with `==`. Anything the analyzer reports fails the
gate, `info` level included — so run it bare, with no path argument and no
grep, or a file-scoped run will hide exactly those.

CI also builds a debug Linux bundle after those checks and verifies that its
executable has no unresolved shared libraries. That keeps the native WebRTC,
LiveKit and desktop plugin graph compiling between release builds. The macOS
and iOS bundles are compiled on every change for the same reason, together
with the `RunnerTests` covering the CallKit and audio-session code Dart tests
cannot type-check.

The macOS build there is driven as `flutter build macos --debug --config-only`
followed by `xcodebuild ... CODE_SIGNING_ALLOWED=NO`, because
`flutter build macos` has no `--no-codesign` and the runner holds no
certificate for the team the project names. Signing stays configured for Debug
on purpose — development builds are custom-signed, see [macOS
keychain](#macos-keychain) — so it is CI that opts out, not the project.

Two suites need more than that:

```sh
flutter test --tags live --run-skipped    # hits meta.discourse.org
flutter test integration_test -d <device> # real app, real network, real storage
```

And one check that is about upstream rather than about this code:

```sh
dart run tool/markup_contract.dart         # see Oneboxes, Mentions, and Polls
dart run tool/flutter_webrtc_contract.dart # verify the vendored 1.6.0 archive
```

GitHub runs those network-dependent checks weekly and on manual dispatch via
`.github/workflows/markup-contract.yml` and
`.github/workflows/flutter-webrtc-contract.yml`. They deliberately do not run
for pull requests: an upstream move or transient fetch failure should report in
those workflows without making an unrelated PR flaky. The WebRTC check accepts
only the file inventory in `third_party/flutter_webrtc/PATCHES.md` after
verifying pub.dev's pinned archive SHA-256.

The live tests are skipped by default (see `dart_test.yaml`) so an offline or CI
run stays green. The integration test is the only one that covers real HTTP,
real redirects and real persistence together.

## Shell layout

The app frame follows Discord's shape. The **instance rail** on the far left is
present at every window size, including phones; everything to its right changes
with the available width.

| Layout     | Width    | Columns                                       |
| ---------- | -------- | --------------------------------------------- |
| `compact`  | < 768    | rail + **one** pane (sidebar *or* content)     |
| `medium`   | 768–1199 | rail + sidebar + content                       |
| `expanded` | ≥ 1200   | rail + sidebar + content + right sidebar       |

On medium and expanded layouts, drag the sidebar's right edge to resize it.
The preferred width is stored once for the app, so it follows the reader when
they switch forums and is restored after a relaunch. Narrow windows temporarily
constrain it to preserve room for the main content without replacing the saved
preference.

Three ways to show something, and they are not interchangeable:

- **Replace the main content** — navigating deeper, e.g. a topic list to a
  topic. Pushes onto a stack so there is a way back. `ShellController.pushContent`.
- **Swap the pane** (compact only) — picking a sidebar entry hands the area next
  to the rail over to the main content. Back returns to the sidebar.
- **A sheet over the shell** — for anything dismissable that should not cost the
  user their place. `showShellSheet` slides up from the bottom and is
  drag-dismissable; on wide windows it is capped and centered rather than
  stretched edge to edge. A picker that belongs to the surface that opened it
  rather than to the shell — the composer's category and tag pickers — passes
  `dialogOnDesktop`, which centers it as a dialog on a pointer platform and
  leaves it a sheet wherever a finger is the only way in.

Back unwinds the content stack first, and only then returns to the sidebar.

### Forum-scoped tabs

On native macOS, Linux, and Windows, each forum owns an ordered workspace shown
in a horizontal tab strip above the main content header. `+` appends and
activates a fresh tab rooted at **Topics**. Sidebar selections, deeper
navigation, and Back change only the active tab's content stack; inactive tabs
keep their route and logical list or topic scroll anchor. Closing the active tab
selects a neighbour, while closing the last tab immediately creates a fresh
Topics tab.

Workspaces are isolated by forum and account. Switching forums restores that
workspace's tab list and active tab, and versioned local persistence restores
route stacks and logical scroll anchors after launch. A composer belongs to
the tab that opened it: switching tabs hides it without changing its origin,
and closing its tab flushes the draft before disposal.

Forum tabs are a native-desktop capability, independent of window width. On a
compact desktop layout, the strip stays with the main content pane and scrolls
horizontally when its tabs no longer fit; the add action remains visible and no
opened-tab count is shown. Command+1 through Command+9 select those ordered tab
positions on macOS; Linux and Windows use Control+1 through Control+9. Back
unwinds the active tab's stack before returning to the sidebar. iOS, Android,
Fuchsia, and web do not show any forum-tab controls; each forum keeps a single
navigation context with no add, switch, or close lifecycle.

### Removing a site

The rail is a column of icons with nowhere to hang a button, so what can be
done to a site lives behind the gesture each platform already means "what else
can this do" — a right click with a pointer, a long press on a touch screen
(`instance_actions.dart`).

The two do not lead to the same place, deliberately:

| | Gesture | Menu holds | Then |
| ---------- | ----------- | -------------- | ------------------------------ |
| desktop | right click | **Remove forum** | confirmation |
| touch | long press | More Options | sheet → **Remove forum** → confirmation |

A pointer lands on a small menu row exactly where it was aimed; a thumb does
not, and the press that opened the menu ends up somewhere inside it. So on
touch the destructive button is one deliberate tap further away, full width in
a sheet. Both paths end at the same confirmation — removing a site signs it out
(see [Disconnecting revokes](#disconnecting-revokes)) and nothing here should be
able to do that by accident.

The rail item's tooltip is set to `TooltipTriggerMode.manual` because its
default trigger on a touch screen is *also* a long press, which would otherwise
name the site under the menu that just opened. Hover ignores the trigger mode,
so the desktop tooltip is unaffected.

Removing a site the user is not looking at leaves them where they are;
`ShellController.removeInstance` follows the selected site to its new index
rather than resetting to its default destination.

### Chrome

Two pieces of chrome sit outside the column structure, both assembled by
`AdaptiveShell`:

- **`ShellPanel`** wraps everything right of the rail. It stops below the status
  bar, rounds the edge facing the rail, and draws one continuous outline around
  its header and content, so the panel sits *on* the backdrop (the scaffold
  background) instead of filling the window. The rail has no panel of its own —
  it draws straight onto the backdrop.
- **`UserBar`** is a card floating over the bottom of the rail and the sidebar.
  Those columns run to the bottom edge *behind* it; `reserveForUserBar` inflates
  the bottom padding they see so their contents stay clear. On compact it gives
  its height back once the main content takes over the pane.

Both cap the system inset they honour rather than taking it whole — the full
home-indicator clearance leaves a floating element visibly stranded above the
edge (see `UserBar.maxBottomInset`).

```
lib/
  main.dart                    minimal production entry point
  src/
    app_bootstrap.dart         ordered, testable startup and platform adapter
    app.dart                   root widget, owns the ShellController
    data/
      discourse_api.dart       site lookup over HTTP
      instance_store.dart      persistence via shared_preferences
    models/                    instance, sidebar and content-route types
    plugins/
      site_plugin.dart         the SitePlugin seam and the const registry
      reactions/               discourse-reactions: models, state, widgets
    shell/
      adaptive_shell.dart      breakpoints and column assembly
      instance_rail.dart       far-left instance column
      instance_actions.dart    right-click / long-press actions on a rail item
      instance_sidebar.dart    per-instance navigation
      main_content.dart        the single main region
      cooked_html.dart         renders a post's cooked HTML
      emoji.dart               draws img.emoji, and resolves its src
      post_footer.dart         picks what a post's footer is, per plugin
      post_likes.dart          the like count under a post, and who liked it
      post_action.dart         one entry in the post menu, core's or a plugin's
      hover_panel.dart         opens a panel when a pointer rests on something
      anchored_layout.dart     places a floating panel against what it is about
      oneboxes/                native rendering of aside.onebox, one file per
                               onebox: github/, discourse/, inline
      code_block.dart          native rendering of pre
      syntax.dart              tokenizes code via package:highlight
      external_link.dart       opens links in the platform browser
      shell_panel.dart         rounded panel wrapping everything but the rail
      title_bar.dart           full-width strip on platforms that hide their own
      user_menu_button.dart    the account avatar and its menu
      shell_sheet.dart         bottom sheet presentation
      add_instance_sheet.dart  the + flow
      empty_state.dart         shown while no sites are connected
      shell_controller.dart    all shell state (plain ChangeNotifier)
      shell_scope.dart         InheritedNotifier access
    theme/app_theme.dart       color schemes + ShellColors/CodeColors
ios/                           iOS runner (Xcode project)
macos/                         macOS runner (Xcode project)
test/                          widget tests, one group per breakpoint
```

State is a plain `ChangeNotifier` so the skeleton carries no state-management
dependency; swapping in Riverpod or Bloc later only touches `shell_scope.dart`
and `shell_controller.dart`.

Release bundle identifier: `org.discourse.native`. macOS debug/profile builds
use `org.discourse.native.dev` so their sandbox data and credential service
cannot overlap the installed TestFlight app.

Dependencies are managed with Swift Package Manager rather than CocoaPods, which
is the default for Flutter 3.44 projects.

## Linux

`webkit2gtk-4.1` and `libsoup-3.0` are hard requirements, not optional extras.
`desktop_webview_window` links them into the binary, so a machine without them
cannot start the app at all — `ld.so` fails at exec and a desktop launcher shows
nothing. They are also what makes signing in work: the web view intercepts the
`discourse://auth_redirect` callback in-process, so unlike a system-browser flow
there is no URL scheme to register with the desktop and no site setting to
change.

Linux does not use libsecret or require a Secret Service. API keys and unsent
draft mirrors are stored in
`$XDG_DATA_HOME/discourse-native/private-storage.json`, falling back to
`$HOME/.local/share/discourse-native/private-storage.json`. The directory is
forced to mode 0700 and the file to 0600; writes are flushed to a temporary file
and atomically renamed over the previous version. Linux credentials and Apple
drafts use the same private whole-file transaction primitive, while retaining
their separate data formats and migration rules.

This is deliberately filesystem-private, not independently encrypted. It
relies on home-directory or full-disk encryption for protection while logged
out, and does not claim to protect secrets from another process already running
as the same user. Actual unattended encryption needs an external key source — a
keyring, passphrase prompt or hardware — which is the dependency this backend
is intended to avoid.

Linux credentials written by builds that used libsecret cannot be read by this
backend. Those users need to reconnect each site once; the old keyring item is
left untouched. Because its server-side API key remains live, it should also be
revoked from the site's authorized-applications page. `APPLICATION_ID` in
`linux/CMakeLists.txt` remains `org.discourse.native`, matching the macOS bundle
identifier and desktop file.

The window has no custom title bar. `ShellTitleBar` is macOS-only, because it
exists to keep the traffic lights clear of the rail on a window that hides its
own title bar. Linux has no traffic lights, and dropping the GTK header bar to
match would mean reimplementing the window controls, drag-to-move and the
resize handles for no functional gain.

### Installing

Ubuntu 22.04+ or Debian 12+, x86-64. Add the repository once:

```sh
sudo curl -fsSLo /usr/share/keyrings/discourse-native.asc \
  https://jjaffeux.github.io/discourse-native/key.asc
```

Check what you just downloaded before trusting it — this key is what tells apt a
package is ours, so a wrong one is worth catching here rather than never:

```sh
gpg --show-keys /usr/share/keyrings/discourse-native.asc
```

The fingerprint should be `F904 D947 00FC B60E A7AF  7F8A F76E E5A2 17CD FCD0`.
Then register the repository:

```sh
echo "deb [signed-by=/usr/share/keyrings/discourse-native.asc] \
https://jjaffeux.github.io/discourse-native/apt/stable stable main" \
  | sudo tee /etc/apt/sources.list.d/discourse-native.list
```

then

```sh
sudo apt update && sudo apt install discourse-native
```

`Depends:` names webkit2gtk and the other linked libraries, so apt pulls them
in — there is no list of libraries to install by hand. That matters more than
convenience here: webkit is linked, not loaded on demand, so a machine without
it cannot start the app at all, and `ld.so` failing at exec shows nothing
whatsoever from a desktop launcher.

For canary builds, point the same line at `apt/canary canary main` instead.
There is also a `.deb` on each [release](https://github.com/jjaffeux/discourse-native/releases)
for anyone who would rather not add a repository.

### Updates

**The app does not update itself.** Updates arrive the way everything else on
the system does:

```sh
sudo apt update && sudo apt upgrade
```

That is a deliberate choice rather than a missing feature. A packaged install
lives under `/usr`, owned by dpkg, where the app could not replace itself
without asking for root — and an app that asks for root to update itself is a
worse thing to have installed than one that does not.

The generic update seam remains — `Updater` in
[updater.dart](lib/src/data/updater.dart), its controller and its sheet — so the
flow can be exercised with a fake and a future platform integration has a
narrow boundary. There is no native updater implementation or dependency in
the app today: [app.dart](lib/src/app.dart) passes `UnsupportedUpdater`, so
`isSupported` is false and the UI never appears.

Publishing, key handling and what to do about a bad build are in
[docs/release-runbook.md](docs/release-runbook.md).

## Adding a platform

The Xcode/Gradle/CMake runners are generated, not hand written. To add one:

```sh
flutter create --platforms=android,windows .
```

Then re-run `tool/generate_app_icons.sh`, which only writes icons for platforms
that are really scaffolded — it tests for the Gradle project and the CMake
project rather than the bare directory, because writing icons into a directory
with no build system behind it is what left orphan `android/` and `windows/`
trees here in the first place.
