# discourse-native

An experimental native Discourse client, built with Flutter.

Currently targets **iOS** and **macOS**. Android, Windows and Linux are planned;
see [Adding a platform](#adding-a-platform).

## Requirements

- Flutter 3.44+ (`brew install --cask flutter`)
- Xcode 26+ with the command line tools, for the iOS and macOS builds

Run `flutter doctor` to check the toolchain.

## Running

```sh
flutter run -d macos                    # macOS desktop
flutter run -d <simulator-id>           # iOS simulator, see `flutter devices`
```

## Connecting a site

The `+` in the rail resolves whatever you type to a real Discourse. The lookup
mirrors DiscourseMobile's `Site.fromTerm` (`js/site.js` in that repo):

1. Bare hosts get `https://`; an explicit `http://` is the escape hatch for
   local development.
2. `HEAD /user-api-key/new` — a 404 means it is not a Discourse, and the
   `Auth-Api-Version` header must be ≥ 2 or the site is too old for an app.
3. Redirects are followed by hand, because the URL we landed on is the one
   worth storing — `package:http` only reports the one originally requested.
4. `GET /site/basic-info.json` for the title, description and icon.

One deliberate difference: DiscourseMobile strips the port from the resolved
URL, which would make a site on `localhost:4200` unreachable. We keep it.

Sites are persisted with `shared_preferences`. Only public metadata goes there.

## Connecting an account

Tapping the user bar runs Discourse's **user API key** handshake, the same one
DiscourseMobile uses (`SiteManager.generateAuthURL` / `handleAuthPayload`):

1. A 2048-bit RSA key pair is generated once per install and kept in the
   keychain. Generation runs in an isolate — it takes seconds.
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

### Topic lists

`latest`, `new`, `unread`, `top` and `messages` all share one envelope
(`topic_list.topics` plus a `users` array), so they go through a single
`DiscourseApi.topicList(path:)`. `bookmarks` has a different shape and still
falls back to the placeholder.

Lists are cached per site and destination — revisiting one does not refetch;
pull-to-refresh forces it. They work signed out too, since `/latest.json` is
public; unread state simply arrives as zero.

Two things the payload makes you handle:

- Poster avatars live in a sibling `users` array keyed by id, and their
  `avatar_template` is usually site-relative with a `{size}` placeholder.
  `TopicList.fromJson` resolves them into each topic so widgets get plain URLs.
- Use `title`, **not** `fancy_title`. The latter is HTML — a title renders as
  `&ldquo;Regular mode&rdquo;` in a `Text` widget. `title` is the same string as
  plain unicode.

### Scrolling

The list is lazy already: `ListView.separated` with an `itemBuilder` is backed
by a `SliverChildBuilderDelegate`, so only rows near the viewport are built.
That is Flutter's virtualization — there is no separate widget for it. (The
non-builder `ListView(children: [...])` form *is* eager; the sidebar uses it,
which is fine for a fixed handful of entries.)

Pagination follows `topic_list.more_topics_url`, with one trap: Discourse
reports it as `/latest?no_definitions=true&page=1` — **no extension**, and that
route serves HTML. `TopicList.nextPagePath` inserts `.json` before the query.

The next page is requested from a scroll notification rather than from
`itemBuilder`, keeping the request out of the build phase, and starts a
screenful early so rows are usually there before the user reaches them.
Topics already held are dropped by id when a page arrives: a topic bumped
between fetches shifts the window and comes back on the following page.

### Topics

Tapping a row pushes a topic route onto the content stack, so back returns to
the list — which is not refetched, since feeds are cached.

`/t/{slug}/{id}.json` returns the first twenty posts **plus the ids of every
post in the topic**, so paging is by id (`/t/{id}/posts.json?post_ids[]=…`)
rather than by page number. Fetched posts are merged in post-number order, not
append order.

Post bodies are the `cooked` field — HTML the site already rendered, with its
markdown, oneboxes, mentions and emoji resolved. `flutter_widget_from_html_core`
draws it; reimplementing any of that client side would be a mistake.

Two things worth knowing if you touch the lists:

- The load-more footer may only appear **while actually loading**. Keying it on
  "there is more" leaves a spinner running forever at the bottom.
- Fetching is triggered both from a scroll notification and from building the
  last row. The scroll alone is not enough: twenty short posts may not fill the
  window, leaving nothing to scroll and the rest never fetched.

`HtmlWidget` renders into a bare `RichText`, which `find.text` and
`find.textContaining` both ignore — widget tests need a `byWidgetPredicate`
finder to assert on post content.

### Links

Every tapped link — in a post, a quote attribution, a onebox card — goes through
[`openLink`](lib/src/shell/open_link.dart), which decides where it belongs:

| Link                                     | Opens                          |
| ---------------------------------------- | ------------------------------ |
| `/t/{slug}/{id}` on the site being read   | here, as a topic route         |
| a topic on another site in the rail       | that site, then the topic      |
| `/u/{username}` on the site being read    | that person's card             |
| anything else                             | the platform browser           |

Two things make this work. Discourse writes its internal links site-relative, so
they are resolved against the current site before anything looks at them
(`ShellController.absoluteUrl`). And sites are matched by **host and port, not
scheme** (`DiscourseInstance.serves`) — a post from 2013 linking to `http://`
still points at the same forum, while two development forums on localhost differ
only by their port.

A link only knows the slug, so a topic opened from one is titled from the slug
until the real title arrives with the topic and replaces it.

### Oneboxes

Oneboxes are the exception to "let `HtmlWidget` draw the cooked HTML". Discourse
styles them entirely from a stylesheet, and `flutter_widget_from_html_core` has
no stylesheet engine — it reads only the `style` *attribute* of individual
elements, and treats a `<style>` tag as non-rendering. So none of Discourse's
`onebox.scss` can be reused here, at any price, and an untouched onebox arrives
as an unstyled pile of text and images.

[`onebox.dart`](lib/src/shell/onebox.dart) draws them natively instead. It does
*not* reimplement one widget per engine — there are dozens and they churn.
It reads the envelope every engine shares, which is `_layout.mustache` upstream:

| Markup                    | Drawn as                                    |
| ------------------------- | ------------------------------------------- |
| `aside.onebox`            | the card, tappable to `data-onebox-src`     |
| `header` → `img.site-icon`, `a` | favicon + site name row               |
| `article.onebox-body` → `img.thumbnail` | lead image, left of the text  |
| … → `h3`/`h4`             | title                                       |
| everything else           | handed back to `HtmlWidget`                 |

That last row is what keeps unknown and future engines working: whatever the
parser has no opinion about still reaches the reader, inside native chrome.
`img.onebox-avatar` is the one engine-specific signal honoured — Twitter and
friends lead with an avatar, which reads wrong as a rectangular thumbnail.

The parser never mutates the DOM it is handed; the body remainder is serialized
back to a string. The document belongs to the caller's `HtmlWidget`.

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
`tool/onebox_contract.dart` diffs the upstream templates and SCSS against
`tool/onebox_snapshot/`:

```sh
dart run tool/onebox_contract.dart             # fails if upstream moved
dart run tool/onebox_contract.dart --update    # accept, then read the diff
```

It is a drift detector, not a source of styling — the SCSS is snapshotted
because it is where the class names the parser matches on are given meaning.

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
`/categories.json?include_subcategories=true` and flattened, because topic rows
look categories up by id and subcategories arrive nested. It is ~185 KB against
~300 KB for `/site.json`.

### Disconnecting revokes

`POST /user-api-key/revoke` runs before the local key is deleted, on both
disconnect and removing a site. Deleting only our copy would leave a live key in
the user's authorized-apps list with nothing tying it back to us. A 404 is
tolerated — older sites lack the route — and so is being offline; the key is
forgotten locally either way, since keeping one we can no longer see is worse.

### macOS keychain

`SecureStore` passes `MacOsOptions(usesDataProtectionKeychain: false)`. The
plugin defaults to the data protection keychain, which needs the
`keychain-access-groups` entitlement — and adding that entitlement makes the
build require a real development certificate:

```
"Runner" has entitlements that require signing with a development certificate.
```

Without one, every keychain call fails with `errSecMissingEntitlement` (-34018)
and the connect flow reports "could not connect". The file-based keychain needs
no entitlement. Once the macOS target is signed with a team, switch the flag
back and add the entitlement together.

`integration_test/keychain_test.dart` covers this — it is the only place the
failure is visible, since unit tests never touch a real keychain.

API keys live in the keychain via `flutter_secure_storage`, keyed by site URL —
never in preferences. (DiscourseMobile keeps them in AsyncStorage, which is not
encrypted; there was no reason to copy that.) The username and avatar *are*
stored in preferences, so a relaunch knows who you are without a round trip.

## Checks

```sh
flutter analyze
flutter test
```

Two suites need more than that:

```sh
flutter test --tags live --run-skipped    # hits meta.discourse.org
flutter test integration_test -d <device> # real app, real network, real storage
```

And one check that is about upstream rather than about this code:

```sh
dart run tool/onebox_contract.dart        # see Oneboxes
```

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

Three ways to show something, and they are not interchangeable:

- **Replace the main content** — navigating deeper, e.g. a topic list to a
  topic. Pushes onto a stack so there is a way back. `ShellController.pushContent`.
- **Swap the pane** (compact only) — picking a sidebar entry hands the area next
  to the rail over to the main content. Back returns to the sidebar.
- **A sheet over the shell** — for anything dismissable that should not cost the
  user their place. `showShellSheet` always slides up from the bottom and is
  drag-dismissable; on wide windows it is capped and centered rather than
  stretched edge to edge.

Back unwinds the content stack first, and only then returns to the sidebar.

### Chrome

Two pieces of chrome sit outside the column structure, both assembled by
`AdaptiveShell`:

- **`ShellPanel`** wraps everything right of the rail. It stops below the status
  bar and rounds the edge facing the rail, so the panel sits *on* the backdrop
  (the scaffold background) instead of filling the window. The rail has no panel
  of its own — it draws straight onto the backdrop.
- **`UserBar`** is a card floating over the bottom of the rail and the sidebar.
  Those columns run to the bottom edge *behind* it; `reserveForUserBar` inflates
  the bottom padding they see so their contents stay clear. On compact it gives
  its height back once the main content takes over the pane.

Both cap the system inset they honour rather than taking it whole — the full
home-indicator clearance leaves a floating element visibly stranded above the
edge (see `UserBar.maxBottomInset`).

```
lib/
  main.dart                    entry point
  src/
    app.dart                   root widget, owns the ShellController
    data/
      discourse_api.dart       site lookup over HTTP
      instance_store.dart      persistence via shared_preferences
    models/                    instance, sidebar and content-route types
    shell/
      adaptive_shell.dart      breakpoints and column assembly
      instance_rail.dart       far-left instance column
      instance_sidebar.dart    per-instance navigation
      main_content.dart        the single main region
      cooked_html.dart         renders a post's cooked HTML
      onebox.dart              native rendering of aside.onebox
      code_block.dart          native rendering of pre
      syntax.dart              tokenizes code via package:highlight
      external_link.dart       opens links in the platform browser
      right_sidebar.dart       optional details panel
      shell_panel.dart         rounded panel wrapping everything but the rail
      user_bar.dart            floating account card
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

Bundle identifier: `org.discourse.native`.

Dependencies are managed with Swift Package Manager rather than CocoaPods, which
is the default for Flutter 3.44 projects.

## Adding a platform

The Xcode/Gradle/CMake runners are generated, not hand written. To add one:

```sh
flutter create --platforms=android,windows,linux .
```
