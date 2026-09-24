# Testing strategy

Tests describe the behavior the application promises at the narrowest layer
that can prove it. The suite has no test-count target: a test earns its place
by protecting a distinct boundary, state transition, regression, or input
class and by making a failure useful to diagnose.

## Suite boundaries

- `test/` owns the application package, including Voice. A production owner normally has one matching
  test file; cross-owner contracts use an explicitly named `*_boundary_test`
  or `*_contract_test` file.
- Shell boundary coverage is partitioned by observable subsystem. Run
  `shell_navigation_integration_test.dart`, `connection_session_integration_test.dart`,
  `topic_reading_integration_test.dart`, `topic_actions_integration_test.dart`,
  `composer_drafts_integration_test.dart`, `reactions_likes_integration_test.dart`,
  or `chat_shell_integration_test.dart` for focused ownership. Together these
  files replace the former `shell_integration_test.dart` monolith and are discovered
  exactly once by the root runner. Shared shell setup belongs in
  `support/shell_test_harness.dart`; scenario-specific fakes stay beside the suite
  that explains them.
- `integration_test/` is reserved for behavior that needs a real platform,
  such as Keychain persistence. Unit tests still cover all controllable
  success, failure, migration, and ordering branches around that seam.
- `darwin/Tests/` owns shared Apple coordinator tests. Run
  `swift test --package-path darwin` on macOS; both app profiles compile the
  same sources into their iOS and macOS runners. Injected callbacks and timeout
  schedulers exercise ordering without requesting real notification permission.
- `lib/discourse_plugin_test.dart` is a test-support entrypoint for plugin
  packages, not a runner. It exports deterministic host adapters; application
  behavior remains in the owning package's test directory.
- Vendored tests under `third_party/` belong to their upstream project. Do not
  restyle or extend them for application behavior.

Use a pure `test` for models, parsing, stores, controllers, and algorithms.
Use `testWidgets` when the contract needs Flutter rendering, semantics, focus,
input, layout, or the binding's deterministic clock. Promote a case to an
integration test only when a platform implementation is the thing under test.

Shell widget tests choose their platform with `TargetPlatformVariant`. A wide
viewport does not imply desktop navigation: iOS and Android retain the mobile
shell on tablets, and Flutter's implicit test platform is Android. Desktop
fixtures use an explicit desktop variant; mobile fixtures open destinations
from Home before interacting with their content.

Repository-structure tests may inspect imports, manifests, lockfiles, or
generated registrants when source ownership or the resolved build graph is the
contract. A source-text assertion must not stand in for behavior that can be
proved through a public API.

Platform-only cases use an explicit conditional `skip` with a diagnostic
reason (for example, `skip: unsupported ? 'requires POSIX modes' : false`). Do
not silently return from a test on an unsupported platform.

Mobile startup also has an AOT smoke fixture:
`flutter run --release -d macos -t tool/mobile_startup_smoke_main.dart` (or an
iOS device with development signing). It renders the production mobile shell
with an available chat panel, opens Chat, and returns to Topics, then exits.
Require all three `PASS` lines and exit code zero. Build 83 crashed in this
path because the optimized panel loop loaded `panel.owner.value` even when
the selected tab had no panel; debug/widget tests did not reproduce it. Keep
the nullable owner lookup outside that loop. The macOS fixture uses the iOS
theme platform so an Apple Silicon Mac can exercise this path in ARM64 AOT
without a connected phone.

## Names and structure

The complete runner name (`group` plus `test`) must say what observable outcome
is expected and, where it matters, under which condition. Prefer
`refreshes the thread and marks its newest message read` to `refresh works`.
Use canonical acronym spelling such as API, ID, URL, HTTP, JSON, HTML, SVG,
and GIF. Preserve the spelling of literal routes, filenames, and wire keys.

Name groups after the production subject or one coherent behavior area. A
group should reduce repetition or separate distinct concerns in a larger
file; it should not become a miscellaneous container. Keep test names
lowercase when they complete the group name. Generated parameter names should
include the value that will identify a failing case.

One test may use several assertions to describe one transition. Split it when
the arrangement drives unrelated actions, when an early failure would hide a
later contract, or when its name has to enumerate several independent
features. Keep setup local unless a fixture makes the scenario more legible;
shared mutable setup is reset for every test.

The complete application suite runs with a random ordering seed. Flutter
prints the chosen seed so an order-dependent failure can be reproduced by
passing that integer in place of `random`. A test must therefore restore all
state it changes instead of depending on another test running first.

## Assertions

Assert at the public behavioral boundary:

- request method, path, and payload plus the resulting model or state;
- visible text, semantics, focus, navigation, or geometry for UI behavior;
- emitted notifications, durable writes, and ordering for stateful behavior;
- exact collection contents and order when both are contractual.

A strict recording transport should assert the complete ordered method/path
list and the meaningful request bodies. Merely consuming every configured
fake response does not prove that the client made the right requests.

Prefer exact cardinality and values over broad presence matchers. After exact
collection equality, do not repeat assertions already implied by that value.
A static interface assignment expresses a compile-time boundary more clearly
than a runtime `isA` assertion whose type is already known.

Avoid assertions on incidental widget ancestry, private implementation steps,
or call counts unless that detail is itself the contract. Accessibility and
layout tests are the intentional exception: semantics, target size, and exact
geometry are their public results.

When a test promises that a condition exposes or withdraws an action, assert
the exact visible control or custom semantics action and, where practical,
activate it. Finding a shared wrapper or generic action key does not prove the
named affordance.

Repeated identical calls are useful when they prove caching, idempotence, or
retry suppression. Name that behavior explicitly and assert the request or
write count so the repetition cannot become an accidental duplicate.

## Async and time

Tests control concurrency instead of waiting for the machine:

- use `Completer` gates for request and write ordering;
- use observable state or listener callbacks to know an operation started;
- advance widget fake time with `tester.pump(duration)`;
- inject a clock, timer factory, or manual scheduler for expiry behavior;
- drain the event queue only when the contract is specifically about queued
  microtasks or events.

Do not use a non-zero wall-clock delay to let work "probably" finish. A real
timeout belongs only in a transport or integration acceptance test whose
contract is the timeout itself. Performance regression tests prefer fixed
input ratios, repeated best-of measurements, and a generous ratio bound. A
fixed pathological input may instead use a generous absolute ceiling when the
regression is catastrophic and a smaller comparison cannot be measured
reliably.

Engine work such as image decoding completes on the real event loop, which a
`testWidgets` body reaches only inside `tester.runAsync`. A placeholder that
animates until the first decoded frame keeps `pumpAndSettle` from returning;
draw static placeholders (`WidgetFactory.debugDeterministicLoadingWidget` for
cooked HTML, reduced motion for a `DSpinner`) unless the decoded frame is
itself the contract. When it is, await the frame inside `tester.runAsync`, for
example with `precacheImage` on the provider of the `Image` already in the
tree, instead of a wall-clock delay. The image cache outlives each test, so
once the event loop has finished a decode between tests, later tests that show
the same bytes draw the frame at once: only the first such test to run fails,
and randomized ordering moves that failure between them. Give every test that
shows the image its placeholder, and check each one run alone.

A bounded short poll is acceptable for an explicit independently scheduled
condition, such as worker-isolate rendering, a cross-process result, or a
filesystem observation, when the platform exposes no deterministic test hook.
Poll the observable condition, enforce a diagnostic deadline, and do not use
the delay as evidence that unrelated async work finished.

## Corpora and parameterized cases

Use a table or generated corpus when several inputs exercise the same
behavior. Every case must retain a diagnostic `reason` or generated name.
If a test name enumerates cases, the body exercises every named case.
Property and totality tests use fixed seeds and assert that the corpus reached
each important branch; a corpus that silently stops exercising its subject
must fail.

Keep separate tests when inputs represent different policies or would need
different failure explanations. Combining cases only to reduce the test count
does not improve the suite.

## Isolation and cleanup

Register cleanup beside resource creation with `addTearDown`; dispose
controllers, close streams and plugin installations, reset test view changes,
and complete or cancel outstanding work. The root
`flutter_test_config.dart` hook provides a fresh in-memory preferences store
for every test. A test that needs stored values sets them explicitly in its own
setup.

In `testWidgets`, tearDowns run after the body has returned, outside the fake
clock. A future created in the body notifies its listeners through the body's
fake zone, which nothing drives any longer, even once it has completed, so a
tearDown that awaits one never finishes. The test then idles until its own
timeout (ten minutes: `testWidgets` passes one explicitly, overriding
`--timeout`), and because the binding's teardown is queued behind the stuck
one, every later test in the file fails. A failing body is when this happens:
Flutter leaves the widget tree mounted after a failure, so a close that
unmounting would have run falls to the tearDown. Release resources whose
cleanup is asynchronous, such as a `DiagnosticsController`, a
`VoiceDiagnosticsController`, or an app that closes one as it unmounts, in a
`finally` inside the body, and check expectations after that `finally` rather
than in it: one that fails ahead of the release skips it.

Fakes expose observed requests and explicit gates. They do not reproduce the
production algorithm or add implicit timing. Put broadly reused fakes in
`test/support/`; keep a scenario-specific fake beside the test that explains
it.

## Review checklist

Before adding or retaining a test, check that:

1. its runner name identifies a distinct behavior;
2. its layer is the narrowest one that proves that behavior;
3. its assertions would fail for a meaningful regression and avoid restating
   another assertion;
4. async completion is deterministic;
5. failure output identifies the input or transition;
6. resources and global test state are restored; and
7. the owning package's format, analysis, and test gates pass.

The exact commands are listed in the README's Checks section and in
`CLAUDE.md`. Run focused tests while editing, then the complete application
gate before merging.
