# Chart native review handoff

Status: **review corrections complete; final native confirmation queued**.
Browser comparison completed; see [rendered evidence](chart-browser-review.md).

## Independent reviewer native pass

Reviewer task `01a08558-4ae6-7db2-bdd6-ee52e8570ff3` launched the isolated
macOS fixture and inspected its real accessibility tree. The Users fixture was
visually and natively checked in ready, loading, empty and error states; its
full/half metric marks retained visible values, synchronized layout and separate
column resize/sort controls. Actual PollCard results were checked through both
the Radio and Checkbox paths after adding a multiple-choice fixture. Their
70/30 and 80/60 marks, selections and native radio/checkbox nodes remained
distinct; confidential counts exposed no marks and the closed zero-vote case
remained zero. Local single- and multiple-choice callbacks accepted selections
without network or account data.

The daily chart exposed one native accessibility node with the current category
and series values. Pointer selection displayed the compact tooltip, Right moved
inspection, the first Escape cleared it, and the second Escape left Chart
unhandled for its ancestor. Light/dark appearance, the interactive header,
tooltip, RTL chart/legend ordering and 360px/200% layout were inspected.

Two visual defects were found and fixed in this independent review:

- Forest and Plum mapped the original primary/tertiary series to one identical
  site accent. `DChartColors.series` now derives a live palette-relative second
  tone only when host roles collapse, preserving distinct series without fixed
  swatches. Native Forest and Plum reinspection showed distinct paired marks.
- The tooltip-anatomy demo retained fixed 128/144px cards at 200% text, causing
  severe wrapping. Its source dimensions now scale with the inherited text
  scaler, with a focused 360px/200% regression. The rebuilt exact-source bundle
  is queued for the final native confirmation of this correction.

No VoiceOver, iOS device or Linux device testing was performed.

## Exact executable source

- Branch: `codex/ui-chart`.
- Implementation: `3c1fb60a44830fd161af196473c05a8ab0029564`.
- Final executable source (rendered reference corrections):
  `1edacc2894f33d4002d02dd37b31baee1e0017b2`.
- `git diff --exit-code 1edacc2894f33d4002d02dd37b31baee1e0017b2 -- lib test packages macos profiles/full/lib pubspec.yaml pubspec.lock .fvmrc`
  passed after the final build (also including `tool/`). Subsequent handoff commits change documentation
  and progress only; executable source remains equal to this commit.
- Flutter 3.47.2 / Dart 3.13.2; root/full locked resolution succeeded and pins,
  dependencies and all tracked lockfiles remain unchanged.

## Bundle and verification

Build command, from this isolated worktree:

```sh
flutter build macos --debug --no-pub -t lib/chart_review_main.dart
```

Final build log: `/tmp/chart-macos-browser-final.log` (success).
The build uses this worktree's `build/`, never the user's main checkout build.
The app was then copied with `ditto` and given a distinct Info.plist identity:

- Bundle: `/tmp/chart-review-eab4-1edacc28/Chart Review eab4.app`
- Display/name: `Chart Review eab4`
- Identifier: `org.discourse.chartrevieweab4`
- URL scheme: `discourse-chart-review-eab4`
- Entry point: `lib/chart_review_main.dart`

Only the copied bundle's name/identifier/URL-type fields were changed. It was
re-signed locally with ad-hoc signing and an explicit review-only entitlement plist:

```sh
codesign --force --deep --sign - --entitlements /tmp/chart-review-eab4-1edacc28/Review.entitlements \
  '/tmp/chart-review-eab4-1edacc28/Chart Review eab4.app'
codesign --verify --deep --strict --verbose=2 \
  '/tmp/chart-review-eab4-1edacc28/Chart Review eab4.app'
```

Deep strict verification passed: **valid on disk; satisfies its Designated
Requirement**, including nested App, FlutterMacOS, WebRTC, objective_c and debug
libraries. Logs: `/tmp/chart-browser-sign.log`, `/tmp/chart-browser-verify.log`,
`/tmp/chart-review-identity.log`.

The build App.framework kernel, original built app's embedded kernel, and copied
review app's embedded kernel have the identical SHA256:

`fb12b550202eafb59c899f0b5c8c3d7f9c10581766c1df53ee8988463a7eefa3`

Each kernel path ends in
`App.framework/Versions/A/Resources/flutter_assets/kernel_blob.bin`.
Machine-readable exact paths, commit and verification output:
`/tmp/chart-review-eab4-1edacc28/evidence.json`.

## Checks completed

- Root/full `flutter analyze --no-pub`: no issues.
  Logs `/tmp/chart-browser-analysis.log`, `/tmp/chart-browser-full-analysis.log`.
- Touched Dart formatting: 10 files, 0 changes. `git diff --check` passed.
- 147 focused tests passed, final seed **24615266**. Log: `/tmp/chart-browser-focused.log`.

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

1. Browser reference comparison is complete and recorded in chart-browser-review.md. During native review, compare the corresponding
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

## Browser correction validation

147 focused tests passed, seed 24615266. Final export plus registered-example checks: 3 passed (`/tmp/chart-browser-export-final.log`). Root/full analysis clean. Browser settings restored and tab closed before final checks/build. Escape bubbling and invalid borrowed-index preservation are covered. Exact current bundle evidence: `/tmp/chart-review-eab4-1edacc28/evidence.json`.

## Pinned main integration

Merged pinned main `e612ad7b47413fa890b35ae3b55a6f6d37b08cf7` into Chart at executable source `1edacc2894f33d4002d02dd37b31baee1e0017b2`. Final Button, Badge, Input, Radio Group and Checkbox owners and coordinator adapters are preserved. Poll keeps final Radio Group/Checkbox interactions; both result presentations use DChartBar. Users differs from pinned main only in its existing metric-bar migration. All non-Chart progress rows equal pinned main. Runner identities, entitlements, pins and lockfiles are unchanged.

193 integration tests passed, seed **4024479176**, including Chart, actual Poll/Users, Radio Group, Checkbox, Button adoption and styleguide tests. Root/full analysis clean. Build, logs, signed entitlement readback and exact source/kernel provenance are committed in `evidence/chart/integration/`. The isolated copied app is signed with explicit debug/JIT entitlements; readback exactly equals the review plist and excludes APS, developer/team/application identifiers. Deep strict verification passed. Three kernels match; executable source equality passed.

Browser evidence remains the completed earlier comparison; it was not repeated. No CUA, browser or native launch occurred during integration. **awaiting_slot** for native review; examples remain baseline.
