# discourse-native — agent guide

An experimental native Discourse client in Flutter (iOS, macOS, Linux). The
README is the design document: most subsystems have a section there explaining
what the code mirrors on the web client and why. Read the relevant section
before changing a subsystem.

## Gates

Every change must pass exactly what CI runs:

```sh
flutter pub get --enforce-lockfile
(cd packages/discourse_resenha && flutter pub get --enforce-lockfile)
(cd profiles/full && flutter pub get --enforce-lockfile)

dart format --output=none --set-exit-if-changed \
  lib test integration_test tool \
  packages/discourse_resenha/lib packages/discourse_resenha/test \
  packages/discourse_resenha/tool profiles/full/lib
flutter analyze
flutter test --test-randomize-ordering-seed=random
(cd packages/discourse_resenha && \
  flutter analyze && flutter test --test-randomize-ordering-seed=random)
(cd profiles/full && flutter analyze)
```

The Flutter version is pinned in `.fvmrc`; the root, Resenha, and full-profile
`pubspec.lock` files are enforced in CI. If you re-resolve dependencies, update
the affected lockfile; if the Flutter pin moves, update the README's
Requirements line with it.

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
  upstream markup. Core snapshots live under `tool/markup_contracts/`; optional
  feature catalogs and snapshots live under their owning plugin's `tool/`
  directory. `dart run tool/markup_contract.dart` checks all of them. When
  changing a parser, check its snapshot, not your memory of Discourse markup.
  Search a cooked DOM
  through `cooked_dom.dart`, never by indexing `Element.children` — that is a
  `FilteredElementList` which rebuilds itself out of `nodes` on every `length`
  and every `[]`.
- A parser that reads a site payload answers with a default rather than
  throwing, a `customWidgetBuilder` declines markup it does not recognise by
  answering null, and the chat preview projector declines a message it cannot
  read rather than mishandling it. All three are stated as generated-corpus
  tests (`wire_payload_totality_test.dart`, `cooked_markup_totality_test.dart`,
  `chat_preview_totality_test.dart`). Each also asserts that its corpus still
  *reaches* every parser, builder or node kind — a guard that stops matching
  would otherwise leave its code untested with the test still green — and the
  wire one reads `lib/` to check that every `fromJson` is either in its corpus
  or named as not being a site payload, so a new parser cannot be forgotten.
- The composer scan is a typing budget, so its growth is timed rather than
  trusted: `markdown_highlight_test.dart` runs each pathological paste shape
  against its own eightfold. Every one of them was a lazy or backtracking
  pattern where a scan knows something the engine cannot — see the README's
  "Composing" section. When adding one, time it at two sizes; a single ratio
  hides the second-order cases.
- Credentials never go in `shared_preferences`; they live behind
  `PrivateStorage` (Keychain on Apple, mode-0600 XDG file on Linux).
  Diagnostics exports must stay redacted — anything captured by
  `recording_http.dart` flows through `diagnostics_redactor.dart`.

## Layout

- `lib/src/data/` — stores, HTTP transport, API client, request coordinators.
- `lib/src/models/` — JSON parsing and domain records.
- `lib/src/shell/` — app frame, navigation, composer, rendering.
- `lib/src/plugins/` — SDK-free bundled features such as chat, poll, reactions,
  local_dates, gifs, and assign; each is optional per site.
- `packages/discourse_resenha/` — the Resenha Dart integration, native CallKit
  adapter, media SDK dependencies, vendored WebRTC fork, and package tests.
- `profiles/full/` — the production application graph and runners which opt
  into Resenha; the repository root remains the SDK-free core graph.
- `lib/src/diagnostics/`, `lib/src/foundation/` — error capture, shared
  primitives.
- Things with exactly one owner, because a second copy drifts:
  `store_diagnostics.dart` (how a persistence failure is classified),
  `cooked_dom.dart` (searching a cooked post's DOM), `diagnostics_text.dart`
  (how a captured field is drawn), `foundation/calendar_day.dart` (what day a
  moment falls on, and what that day is called),
  `foundation/private_file_document.dart` (how an owner-only whole-file update
  is serialized and committed), `data/serial_operation_queue.dart` (how reads
  observe already-accepted preference writes), `data/origin_request_gate.dart`
  (how per-origin concurrency, bounded backlogs, cooldown policies, leases, and
  shutdown are coordinated), `foundation/loopback_host.dart` (which hosts may
  use plaintext development transports),
  `plugins/chat/chat_message_timeline.dart` (how canonical chat-message ids are
  merged across pages, live arrivals, and the seam back to the present),
  `packages/discourse_resenha/lib/src/resenha_diagnostics_report.dart` (how
  ordinary and deep Resenha diagnostics are sanitized, de-duplicated, and
  merged).
- Root tests live under `test/`; Resenha tests live under
  `packages/discourse_resenha/test/`. A change to `foo.dart` almost always has
  a `foo_test.dart` in its owning package to extend. Follow
  `docs/testing.md` for suite ownership, naming, assertions, async control,
  and cleanup.
