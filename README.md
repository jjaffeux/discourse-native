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
  the current user again, so every avatar it draws for the reader is the new
  one, and reloads the reader's profile page if one is open.

`ProfileAvatarTransactions` owns the two-step write per account session. A
second change is refused while one is in flight, because the site applies
picks in arrival order. A retired session aborts its upload and its late
answer is dropped.

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
