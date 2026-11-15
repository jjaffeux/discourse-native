# discourse-native

wip

See [Application ownership](docs/architecture/README.md) for service, account,
request, and feature boundaries. [Composer ownership](docs/composer-architecture.md)
covers the live editor, built-in component modules, and plugin extension points.

## User profiles

A person's profile is a native page. It mirrors the web client's
`/u/{username}/summary`: who the person is, then their summary or their
activity.

- **Links.** `/u/{username}` and `/u/{username}/summary` open the profile.
  `/u/{username}/activity` and its filters open the activity page, for a
  signed-in reader. Every other page under `/u/{username}`, such as
  preferences, badges and another person's messages, opens in the browser. A
  plain click on a `/u/{username}` link still opens the user card first, and
  the card's **View profile** button opens the page.
- **Layout.** The identity is the page heading, as on the reader's own
  summary, so the name is shown once. The Summary and Activity line tabs stay
  below it while the chosen section scrolls, starting at the bio. A section's
  own choices use the filled tab list, so they do not read as a second row of
  page tabs.
- **Endpoints.** The header reads `/u/{username}.json`. Its `user` object is a
  superset of the card's, and adds the full `bio_cooked`, `last_seen_at` and
  `profile_hidden`. The Summary section reads `/u/{username}/summary.json` and
  the Activity section reads the same feed as the activity page.
- **Hidden.** When `profile_hidden` is true, the page shows the identity the
  site sent and a notice. It shows no Summary or Activity section and asks for
  neither.
- **Missing.** A 404 shows a message with no retry. A 401 or 403 says the
  profile cannot be seen. Any other failure offers a retry.
- **Anonymous.** A reader with no account still loads the header from a public
  site. The Summary and Activity sections ask them to connect the account.

`UserProfileController` holds each profile per account session and username,
so a response for a retired session or a superseded request is dropped.

### Editing your own profile

The Profile tab of Preferences edits what the reader's own profile shows.

- **About me.** The field reads `bio_raw` from `/u/{username}.json` and saves
  it with the same `PUT /u/{username}.json` the web client sends. It is its
  own preference section, `about`, so the half-typed text is never sent by the
  timezone's immediate save, and a bio the site refuses does not hold the
  timezone back. Nothing is sent until the reader presses **Save**. The site
  enforces the 3000-character limit and watched words, and its message is
  shown as it arrives. When `can_change_bio` is false, single sign-on owns the
  bio and the field is read-only. A saved bio reloads the reader's profile
  page if one is open.
- **Refresh.** Reloading Preferences takes the site's values for what the
  reader has not touched and keeps every section that still waits for its own
  save, such as a typed bio. A choice that saves itself is unsaved only after
  its save failed, and a refresh shows what the site holds for it.
- **Picture.** A change is written at once and is not part of any draft.
  **Change picture** uploads the chosen image to `/uploads.json` with
  `upload_type=avatar`, then sends `PUT /u/{username}/preferences/avatar/pick`
  with that `upload_id` and `type=custom`. **Use default** sends the same
  request with `type=system`, which returns to the letter avatar. Both are
  ordinary writes under the `write` scope of the user API key. The row shows
  only what `/u/{username}.json` allows: nothing without `can_edit_avatar`,
  no upload without `can_upload_avatar`, and **Use default** only while
  `uploaded_avatar_id` is set. Gravatar, selectable avatars and avatars from a
  linked account are not offered. After the site accepts a pick the app reads
  the current user again, and reloads the reader's profile page and stored
  user card if it has them.

`ProfileAvatarTransactions` owns the two-step write per account session. A
second change is refused while one is in flight, because the site applies
picks in arrival order. A retired session aborts its upload and its late
answer is dropped.

Posts, cards and messages that were already loaded keep the avatar URL they
were read with. `OwnAvatarOverrides` records, per site, the avatar templates
the signed-in account replaced from this app and the template it draws from
now. `AvatarImage` asks it when an `AvatarOwner` above names whose picture it
is. `UserCardTarget`, the user card header and the hover preview each set one.
Only a URL resolved from a replaced template is redrawn, at the size it was
read at, and only under the reader's own name, because a letter avatar's
template is shared by everyone with that letter and color. A row read after
the change is left as the site sent it. The record has its own notifier, so a
change redraws those avatars and nothing else, and it is dropped when the
account changes. `DiscourseUser` keeps `avatar_template` for this. An avatar
drawn outside an `AvatarOwner` shows the old picture until its list reloads.

### Users, email and security preferences

The app signs in with a Discourse user API key. Its `write` scope reaches
every route (`app/models/user_api_key_scope.rb`), but the key carries no
browser session. A Preferences tab is native where the action needs only the
key, and opens the web page where core asks for a confirmed session or a
secret.

- **Muted users.** The Users tab lists `muted_usernames` from
  `/u/{username}.json` as removable chips, with a search that adds people
  through `/u/search/users.json`. The list is the `users` preference section.
  It waits for **Save**, survives a refresh while unsaved, and is sent whole
  as one comma-separated `muted_usernames` field of `PUT /u/{username}.json`,
  which is how core's `UserUpdater` reads it. The search never offers the
  reader. Without `can_mute_users` the tab says the account may not mute yet.
- **Ignored users.** Ignoring is not part of that draft. Core takes it one
  person at a time on `PUT /u/{username}/notification_level.json`, where the
  username is the person ignored, with `notification_level=ignore` and an
  `expiring_at` date. **Ignore** sends it at once for the chosen time, and
  **Stop ignoring** sends `notification_level=normal`. The web client offers
  calendar shortcuts in the reader's timezone. The app offers eight lengths
  counted from now, and "forever" is the web client's thousand years, because
  core has no ignore without an end. Core lifts a mute of the same person in
  both directions, so the muted list drops them as well. The list and its
  controls are absent without `can_ignore_users`, which core grants by group
  (`ignore_allowed_groups`).

`IgnoredUsersTransactions` owns the request per account session and has its
own notifier. It composes `AccountWrites`, which holds what every immediate
account write shares: one request at a time per site, because the site
applies them in arrival order, a state that names what the request is about,
and an answer dropped when its session retired. An accepted write is recorded
with `PreferencesController.confirmOutsideSections`, which patches the
confirmed value and the draft and discards a read that began before it.

## Native image build tools

AVIF stills and animations use the source-built `flutter_libavif` decoder.
Install its build tools before running Flutter tests or building the app:

```sh
brew install cmake meson ninja nasm rustup
export PATH="$(brew --prefix rustup)/bin:$PATH"
rustup toolchain install 1.92.0 --profile minimal
export RUSTUP_TOOLCHAIN=1.92.0
```

On Linux, install `cmake meson ninja-build nasm` and [rustup](https://rustup.rs),
then select the same Rust toolchain. Apple cross-builds also need the target,
for example `rustup target add --toolchain 1.92.0 aarch64-apple-ios`.
CI installs these tools through `.github/actions/setup-avif`.

## TestFlight build setup

Install the Ruby dependencies and the Xcode build log formatter before running
Fastlane:

```sh
bundle install
brew install xcbeautify
```

Fastlane adds Homebrew's `rustup` to `PATH` and selects Rust `1.92.0`
automatically for every lane.

Both iOS and macOS TestFlight builds use `xcbeautify`, the
[formatter recommended by Fastlane](https://docs.fastlane.tools/best-practices/xcodebuild-formatters/).

## Google Play internal testing

See [Deploy an Android build to internal testing](docs/android-testing.md) for
Android SDK setup, upload signing, the first Play Console upload, and the
`fastlane android build` and `fastlane android beta` commands.

With both stores' credentials configured, the existing release command builds
all three platforms and publishes Android to internal testing:

```sh
bundle exec fastlane beta version:1.1.0 skip_checks:true
```

Apple build numbers come from TestFlight. Android selects the next version code
from the app bundles and APKs in Google Play, independently of the version name.
