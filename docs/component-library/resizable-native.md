# Current integrated review bundle

Supersedes the older bundle/evidence below. Integration only; **awaiting_slot**.

- Pinned main merged: `e612ad7b47413fa890b35ae3b55a6f6d37b08cf7`.
- Exact source/merge commit: `0629571a58e927f480c03de909bdfd4f676cdbd1`.
- Bundle: `/tmp/discourse-resizable-integration-0629571a/ResizableIntegration.app`.
- Name: Resizable Integration 0629571a; ID:
  `org.discourse.native.resizable.integration0629571a`; URL scheme:
  `resizable-integration-0629571a`.
- Entrypoint: `lib/resizable_review_main.dart`. Existing Runner debug scheme
  built in this isolated checkout; copied bundle alone receives unique identity.
- Kernel SHA256 (app.dill, built bundle and copied bundle identical):
  `2ffa27d7519d1edc17b8d8da3f204814298a298c4ae4b3c5cb10b76526f46840`.
- Explicit ad-hoc signing uses the preserved `integration/debug.entitlements`.
  Signed readback exactly equals that plist: sandbox, allow-jit, network
  client/server, user-selected read/write, audio-input and camera are true.
  No APS, team/application identity or `com.apple.developer.*` entitlements.
  Deep strict signature verification passes; launch eligibility remains untested.
- 180 focused tests pass (component/styleguide/pane/controller/Users/Chat plus
  Topic Inbox and Group ownership). Root/full-profile analysis clean; touched
  formatting and diff checks pass. Production runners, pins and lockfiles equal
  pinned main. All non-Resizable progress rows exactly match pinned main.
- Current Button export resolves the existing styleguide usage to final Button;
  no unmerged owner or substitute input was added. Current main Group/Sidebar/
  Topic Inbox changes are retained; resize constraint/collapse owner unchanged.
- Evidence: `evidence/resizable/integration/`. Subsequent commits are metadata only.

No CUA, browser navigation, native launch or blocker retries were attempted.
Mac remains locked; browser navigation is separately denied by admin-policy
verification. Park until coordinator explicitly resumes browser/native review.

---

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
