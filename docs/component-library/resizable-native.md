# Resizable native review handoff

Status: **awaiting_slot**, in_progress. No native app or browser was launched.
The Mac remained locked; native visual/accessibility inspection is pending.

## Source and build equality

- Source commit: `7ba6dd15a5134b195d8b9fb5fda6e457e8005eb0` on `codex/ui-resizable`.
- Build checkout: `/Users/joffreyjaffeux/.codex/worktrees/c1fc/discourse-native`.
- Entrypoint: `lib/resizable_review_main.dart`, mounting actual production pane,
  Matrix column and Chat thread adapters with local widths/counters only,
  plus all Resizable examples and a button opening the real styleguide.
- Final command: `flutter build macos --debug --no-pub -t lib/resizable_review_main.dart`.
- Flutter 3.47.2; final build succeeded. The only emitted build warning was the
  existing always-run Flutter Assemble script phase. Root/full lockfiles and
  `.fvmrc` remain unchanged. No Voice compatibility code changed.
- Source equality checked with `git diff --exit-code 7ba6dd15a5134b195d8b9fb5fda6e457e8005eb0 -- lib test macos .fvmrc pubspec.lock profiles/full/pubspec.lock packages/discourse_voice/pubspec.lock`.
  Subsequent handoff metadata commits change documentation only.

The final build was rerun after the final standalone API cleanup commit; this is not the
kernel from the earlier pre-format build.

## Isolated bundle

`/tmp/discourse-resizable-review-c1fc/DiscourseResizableReview.app`

- Display name: **Discourse Resizable Review**.
- Main executable: `DiscourseResizableReview`.
- Bundle ID: `org.discourse.native.resizable.c1fc`.
- URL scheme/name: `discourse-resizable-c1fc` / `org.discourse.native.resizable.c1fc`.
- Built with the checkout's Runner debug scheme, copied with `ditto`; only the
  copied root Info.plist and main executable name were changed to isolate the
  review identity. No real app bundle or settings were modified.
- Re-signed locally with `codesign --force --sign - --entitlements macos/Runner/DebugProfile.entitlements <bundle>`.
- `codesign --verify --deep --strict --verbose=2 <bundle>` succeeded, reporting
  **valid on disk** and **satisfies its Designated Requirement**. Nested
  frameworks and debug dylibs passed strict verification.

SHA256 of each of the following is identical:
`564d2ae4fcee4c667fbd4aa80521d3454cef17195e76723758130b1398918b1b`

1. `.dart_tool/flutter_build/184cab88fda9e046b73a03cb7637d050/app.dill`
2. `build/macos/Build/Products/Debug/Discourse.app/Contents/Frameworks/App.framework/Versions/A/Resources/flutter_assets/kernel_blob.bin`
3. `/tmp/discourse-resizable-review-c1fc/DiscourseResizableReview.app/Contents/Frameworks/App.framework/Versions/A/Resources/flutter_assets/kernel_blob.bin`

## Independent checks complete

- Root and full-profile enforced-lockfile pub resolution: pass.
- Root and full-profile static analysis: no issues.
- Touched Dart formatting and `git diff --check`: pass.
- 88 focused component/styleguide/pane/controller/Users/Chat regression tests:
  pass. Final radius correction additionally passed 16 component/styleguide
  tests, including custom zero radius, 48px coarse input regions and RTL edge
  drags. Four extracted complete usage programs pass Dart analysis.
- Logs are preserved under [evidence/resizable](evidence/resizable/).

## Required desktop review after unlock

Coordinator grants a serialized slot before any CUA/browser/native action.
Compare official rendered Base Nova examples against actual Flutter at matching
size/state/text scale in light/dark, then test custom palette/radius, RTL and
large text. Check 1px line and 4×24 pill, source-inferred label typography and
preview height against computed reference styles; do not infer parity from
these tests. Exercise keyboard focus, Home/End, arrows, Enter, pointer collapse
threshold/cancellation, nested boundaries, controlled/dynamic/disabled state.
Inspect the actual styleguide and each production adapter fixture. VoiceOver
and iOS/Linux device behavior remain unverified. The row must remain
in_progress until this gate is complete; coordinator alone reviews/merges.
