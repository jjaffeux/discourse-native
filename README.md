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
      right_sidebar.dart       optional details panel
      shell_panel.dart         rounded panel wrapping everything but the rail
      user_bar.dart            floating account card
      shell_sheet.dart         bottom sheet presentation
      add_instance_sheet.dart  the + flow
      empty_state.dart         shown while no sites are connected
      shell_controller.dart    all shell state (plain ChangeNotifier)
      shell_scope.dart         InheritedNotifier access
    theme/app_theme.dart       color schemes + ShellColors surfaces
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
