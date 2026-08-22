# discourse-native — agent guide

An experimental native Discourse client in Flutter (iOS, macOS, Linux). The
README is the design document: most subsystems have a section there explaining
what the code mirrors on the web client and why. Read the relevant section
before changing a subsystem.

## Gates

Every change must pass exactly what CI runs:

```sh
dart format --output=none --set-exit-if-changed lib test integration_test tool
flutter analyze
flutter test
```

The Flutter version is pinned in `.fvmrc`; `pubspec.lock` is enforced in CI
(`flutter pub get --enforce-lockfile`). If you re-resolve dependencies, the
pin, the lockfile, and the README's Requirements line must move together.

## Conventions that are easy to miss

- Commit subjects use `FIX:` / `UX:` / `REFACTOR:` prefixes with a detailed
  body explaining the why; history merges topic branches with `--no-ff`.
- Comments state constraints and intent, never narration. There are no TODOs
  in the tree; do not introduce any.
- Controllers must stay usable from pure Dart — VM tests, `tool/` scripts and
  secondary isolates construct them with no Flutter binding. Nothing reachable
  from a controller may require `SchedulerBinding.instance` to exist (see
  `FrameSafeNotifier`, pinned by `test/frame_safe_notifier_headless_test.dart`).
- Async races are treated as first-class bugs. Stale reads must not clobber
  newer state: follow the existing generation/version-token patterns
  (`SecureStore`, `_SessionValue` in `ShellController`) and add a test in the
  style of `shell_async_ordering_test.dart` / `shell_credential_read_races_test.dart`.
- Rebuild isolation is deliberate architecture: `ShellController` is a facade,
  and independently-changing state (search, chat, reactions, update progress…)
  lives on its own notifier so typing or paging never redraws the shell. Widget
  listening goes through `ShellScope` / `ShellSelector`.
  `shell_rebuild_isolation_test.dart` pins this; keep new state out of the
  facade's `notifyListeners()` unless it is genuinely shell-wide.
- `shell_controller.dart` being the largest file is a consequence of that
  facade, not a backlog item. Splitting it has been measured: the composer
  submit path, the instance-order cluster and `_forgetSiteState` are each
  bidirectionally wired to navigation, topic state and the sub-controllers at
  once, and the one genuinely clean seam (the hashtag/mention identity caches)
  is ~4% of the file. Extracting state that *does* change independently is
  welcome — that is how the eleven existing sub-controllers got there — but
  moving lines to shrink the file is not, and has been declined deliberately.
- Cooked-HTML parsers (oneboxes, hashtags, polls, local dates) depend on exact
  upstream markup. The upstream sources are snapshotted under `tool/*_snapshot/`
  and checked by `dart run tool/markup_contract.dart`; when changing a parser,
  check the snapshot, not your memory of Discourse markup.
- Credentials never go in `shared_preferences`; they live behind
  `PrivateStorage` (Keychain on Apple, mode-0600 XDG file on Linux).
  Diagnostics exports must stay redacted — anything captured by
  `recording_http.dart` flows through `diagnostics_redactor.dart`.

## Layout

- `lib/src/data/` — stores, HTTP transport, API client, request coordinators.
- `lib/src/models/` — JSON parsing and domain records.
- `lib/src/shell/` — app frame, navigation, composer, rendering.
- `lib/src/plugins/` — chat, resenha (voice rooms), poll, reactions,
  local_dates, gifs, assign; each is optional per site.
- `lib/src/diagnostics/`, `lib/src/foundation/` — error capture, shared
  primitives.
- `test/` mirrors these by name; a change to `foo.dart` almost always has a
  `foo_test.dart` to extend.
