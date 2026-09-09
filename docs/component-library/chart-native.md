# Chart native review handoff

Status: **awaiting_slot**. No browser/CUA/native app launch has been performed.
The Mac remains locked. Source/build readiness does not satisfy the visual gate.

## Exact executable source

- Branch: `codex/ui-chart`.
- Implementation: `3c1fb60a44830fd161af196473c05a8ab0029564`.
- Final executable source (formatting-only follow-up):
  `083fa3dc9ddae9e395097e46782a8d43cc560682`.
- `git diff --exit-code 083fa3dc9ddae9e395097e46782a8d43cc560682 -- lib test packages macos profiles/full/lib pubspec.yaml pubspec.lock .fvmrc`
  passed after the final build. Subsequent handoff commits change documentation
  and progress only; executable source remains equal to this commit.
- Flutter 3.47.2 / Dart 3.13.2; root/full locked resolution succeeded and pins,
  dependencies and all tracked lockfiles remain unchanged.

## Bundle and verification

Build command, from this isolated worktree:

```sh
flutter build macos --debug --no-pub -t lib/chart_review_main.dart
```

Final build log: `/tmp/chart-macos-build-final.log` (success).
The build uses this worktree's `build/`, never the user's main checkout build.
The app was then copied with `ditto` and given a distinct Info.plist identity:

- Bundle: `/tmp/chart-review-eab4-083fa3dc/Chart Review eab4.app`
- Display/name: `Chart Review eab4`
- Identifier: `org.discourse.chartrevieweab4`
- URL scheme: `discourse-chart-review-eab4`
- Entry point: `lib/chart_review_main.dart`

Only the copied bundle's name/identifier/URL-type fields were changed. It was
re-signed locally with ad-hoc signing and preserved entitlements:

```sh
codesign --force --deep --sign - --preserve-metadata=entitlements \
  '/tmp/chart-review-eab4-083fa3dc/Chart Review eab4.app'
codesign --verify --deep --strict --verbose=2 \
  '/tmp/chart-review-eab4-083fa3dc/Chart Review eab4.app'
```

Deep strict verification passed: **valid on disk; satisfies its Designated
Requirement**, including nested App, FlutterMacOS, WebRTC, objective_c and debug
libraries. Logs: `/tmp/chart-review-sign.log`, `/tmp/chart-review-verify.log`,
`/tmp/chart-review-identity.log`.

The build App.framework kernel, original built app's embedded kernel, and copied
review app's embedded kernel have the identical SHA256:

`8a93ab451b3e0f16914a276deef3d2f4adf9f385bc9b9275a93d48e854da691e`

Each kernel path ends in
`App.framework/Versions/A/Resources/flutter_assets/kernel_blob.bin`.
Machine-readable exact paths, commit and verification output:
`/tmp/chart-review-eab4-083fa3dc/evidence.json`.

## Checks completed

- Root/full `flutter analyze --no-pub`: no issues.
  Logs `/tmp/chart-final-analysis.log`, `/tmp/chart-final-full-analysis.log`.
- Touched Dart formatting: 10 files, 0 changes. `git diff --check` passed.
- 146 focused tests passed, final seed **1577084355**. Log: `/tmp/chart-final-focused.log`.

```sh
flutter test --no-pub \
  test/d_chart_test.dart \
  test/styleguide/chart_examples_test.dart \
  test/chart_review_fixture_test.dart \
  test/poll_card_test.dart \
  test/users_page_test.dart \
  test/poll_integration_test.dart \
  test/poll_shell_controller_test.dart \
  --test-randomize-ordering-seed=random
```

An additional 15 existing styleguide-page/Button-adoption integration tests
passed (seed 2936222072), log `/tmp/chart-styleguide-integration.log`.

The component tests verify pointer/keyboard/RTL inspection and current/next/
previous semantics; hidden/custom keys and content; borrowed controller/focus
replacement/removal; live palette/radius/multiplicative alpha; negative/null/zero
values; directional quantitative marks; and an actual rendered-image paint
check. The styleguide tests exercise all ten examples at 260px/200%/RTL and
switch the real daily-series choice. The fixture test mounts actual UsersPage
and PollCard, tests empty/ready transitions and verifies confidential counts
produce no quantitative marks. Existing downstream tests preserve maxima,
column widths/scroll ownership, invalid input, accepted-result and account-race
behavior. These tests are not device, VoiceOver or pixel-parity verification.

## Required serialized review after unlock

1. Compare the official frozen page's actual renders to the corresponding
   styleguide steps, interactive header, tooltip treatments, custom content and
   Arabic RTL at matched geometry. Source-derived measurements and all frozen
   section accounting are in `chart.md`; inspect/correct actual differences.
2. In the isolated app, inspect actual UsersPage ready/loading/empty/error;
   its column-width persistence is memory-only. Inspect Poll visible results,
   confidential results, closed/zero votes, Pending, and Fail next vote / retry.
   No account, network or production store is needed.
3. Open Styleguide using the fixture's button, select Chart, and inspect light,
   dark, Forest/Plum, narrow/large text, RTL, reduced motion, hover/touch-style
   click, keyboard arrows/Home/End/Escape, outside dismissal and live color
   changes during controlled inspection. Confirm content fits and is legible.
4. Record exact surfaces/observations and remaining platform limits, correct
   differences, then promote the progress row/examples only after coordinator
   review. Quit only this review app and close only task-created reference tabs.

No push, GitHub write, release action, real-app overwrite or App Store Connect
operation occurred. Coordinator alone performs the final local merge.
