# Progress implementation checkpoint

Status: in_progress; nativeInspectionStatus: awaiting_slot. No reference browser
or native app was opened. Do not infer rendered fidelity from source or tests.

## Reference captured 2026-09-09

The frozen 2026-09-08 scope remains unchanged (Progress catalogue sections:
Usage, Composition, With label and value, Label, Controlled, RTL, API Reference).

| Source | SHA256 |
| --- | --- |
| https://ui.shadcn.com/docs/components/base/progress.md | `7e0420446e2f8aef2323fc2de6695d58f4bff55762eca3192d83570b81706ef9` (identical to frozen catalogue) |
| https://ui.shadcn.com/r/styles/base-nova/progress.json | `359e72beff723311ec2e4d5154a0f80dedd253bd6b16959a4db0773714ceab52` |
| Decoded registry component | `2c104695a495968e9ee426039e291abc4fb2ff32f36b5faa4e8b450c2a4cc14c` |
| https://raw.githubusercontent.com/mui/base-ui/master/packages/react/src/progress/indicator/ProgressIndicator.tsx | `ff49a4c568fe92bd180ab13f21c94d05deab1b19bc0a42ed255fc17cfb39406e` |

Sources are captured alongside this document. Base UI's API page
https://base-ui.com/react/components/progress was also read. Shadcn source uses
the repository's reference/LICENSE.shadcn.md; Base UI MIT license is included.

## Source-to-Flutter metrics and APIs

CSS px map to logical px at 100% text scaling and 16px root rem.

| Reference | Flutter |
| --- | --- |
| Root flex-wrap, gap-3 | Label/value header Wrap with 12px gap/run gap; 12px to full-width track. A lone track receives parent height constraints directly. |
| Track h-1, w-full, rounded-full, overflow-x-hidden, bg-muted | 4px track; radius height/2; ClipRRect; live DTokens.muted. Explicit width or finite parent width required. |
| Indicator h-full, bg-primary | Full track height, logical-start fraction width, live DTokens.primary. |
| transition-all | 150ms width transition, standard cubic (0.4,0,0.2,1), no initial entrance animation; disabled with reduced motion. |
| Label text-sm font-medium | DLabel composition with DiscourseTypography.sm (14px), 20px line height, weight 500. |
| Value text-sm, muted-foreground, tabular-nums, ml-auto | 14px/20px, weight 400, live muted foreground, tabular figures; header distributes label/value to opposite ends and wraps at narrow widths. |
| Demo w-[60%], 13 → 66 after 500ms | FractionallySizedBox(.6), cancellable local timer, Replay action. |
| Label/controlled/RTL max-w-sm | 384px maximum example width, fills narrower parents. |

Public `DProgress` supplies min/max/value and a shared composition scope.
`DProgressTrack`, `DProgressIndicator`, `DProgressLabel`, `DProgressValue` are
exported from discourse_ui.dart. Default label/value/track slots cover normal
composition; child supplies arbitrary caller-owned layout of the same parts.
Track supports application height/width/color; indicator supports color. No
Discourse services or networking enter the reusable implementation.

The caller owns values and asynchronous work (ordinary state or
ValueListenableBuilder). This read-only component has no FormField, mutable
controller, focus node, pointer action, or adjustable keyboard semantics.
Finite values clamp to finite min/max (max must exceed min); default range is
0–100. Extreme finite ranges avoid subtraction overflow. Null/NaN/infinity
mean unknown progress. Value builders receive the normalized fraction or null
for localized digits/units. The semantic range is normalized 0–100, numerical,
with no fabricated range for unknown work. A visible DProgressLabel supplies
the accessible name, or callers supply semanticsLabel. DProgressValue is
excluded from duplicate spoken value content. Updates do not force a live
region on every network progress event; production status announcements remain.

## Specific adaptations and dependencies

- Unknown Base UI indicator has no width style and shadcn adds no indeterminate
  width. Existing native async strips must visibly convey work: a one-third
  segment moves over 1400ms, reverses logically in RTL, and stays at start under
  reduced motion. TickerMode disables its ticker; disposal cancels it.
- Flutter 3.47 requires value/min/max for the progressBar semantic role. Unknown
  work therefore uses loadingSpinner semantics; known work uses progressBar.
  No claimed VoiceOver speech result without actual testing.
- Application strips retain 2px thickness and composer upload 3px; root respects
  a parent's 2px height even with the default 4px track. Users retains its green
  domain palette. Default reusable track remains the reference 4px.
- Font family and semantic colors follow the app's inherited theme. Text scaling
  remains inherited; label/value can wrap instead of clipping to reference height.
- Label is merged. Slider remains a separate unmerged component: Controlled uses
  baseline DButton actions, with explicit pending integration note. Button's
  baseline API is not relabeled implemented. Six actual-component examples
  remain baseline until rendered/native review passes.

## Adoption audit

All 15 LinearProgressIndicator call sites in 14 owned files migrated:

- Core: badges_page, categories_page and tags_page refresh strips;
  users_page loading state; composer_panel upload queue (fractional max:1,
  upload progress and error/retry/cancel ownership unchanged); update_sheet
  download (fractional max:1 and existing live status announcements);
  bookmark_ui mutation; post_revision_history loading.
- Chat: chat_pinned_bar loading. Assign: assignment_sheet search and
  assigned_group_view member loading/loading-more. Events: event_card pending
  response and unavailable refresh, event_directory calendar strip,
  event_participants loading.
- All bundled plugin source searched. Other plugins have no matching linear
  indicator. Keep DSpinner activity indicators, group directory/member spinners
  and skeletons, poll result percentages, topic reading/scroll progress, media
  seek/buffer timelines and Voice activity unchanged: these have different
  interaction or domain meaning. Chat upload status ownership is unchanged.
- packages/video_player_avfoundation/example/lib/mini_controller.dart's three
  upstream linear indicators are a vendored demonstration, not owned app UI;
  retain verbatim. No dependency, lockfile, Flutter pin or runner source changed.

UpdateDownloadProgress is the real read-only update-sheet body extracted for
safe review without an updater. The original controller still owns status and
all actions. Adjacent Button/Input/Badge changes belong to their own tasks and
must be reconciled by the coordinator when merging.

## Verification actually performed

Root and profiles/full `flutter pub get --enforce-lockfile` passed with unchanged
lockfiles. Root and profiles/full `flutter analyze --no-pub` passed without
issues. Touched-file formatting and git diff --check pass.

302 focused tests passed (seed 9092026), log `/tmp/progress-final-tests.log`:
DProgress, Progress examples, offline fixture, update sheet accessibility/update
controller, Assigned group view, composer upload panel, Events card/lifecycle,
Badges/Categories/Tags/Users pages, Events directory/participants, Bookmark UI,
revision history/ownership, Chat channel lifecycle, assignment sheet and Button
adoption. After source timing/typography/example-width refinements, 10 focused
component/example/fixture tests passed again (`/tmp/progress-final-component.log`).
These include extreme finite range, thin constrained strips, TickerMode,
null/non-finite transitions, semantics, live palette, narrow 200% RTL, geometry,
controlled keyboard input and actual in-memory upload/download updates.

Earlier focused checks caught and fixed a thin-strip Column overflow and the
unknown progress role assertion. An initially listed Chat test filename did not
exist; the final run uses its actual Chat channel lifecycle owner. The full
suite was not run, per the user's explicit scope.

## Offline native review bundle (not yet launched)

Entrypoint: `tool/progress_review_main.dart`. It mounts real
ComposerUploadQueue with a local uploader, UpdateDownloadProgress with no update
or install action, EventUnavailableCard and BadgesPage with local data. Controls
change palette, RTL, text scaling, motion, loading and percentages, and open the
real ComponentStyleguidePage. No credentials or network clients are created.
The fixture's widget test verifies real upload/download updates and cleanup.
Other migrated screens have focused regression coverage but no native inspection
claim. Native review should inspect both the styleguide and these fixtures.

Build: `flutter build macos --debug --no-pub -t tool/progress_review_main.dart`.
Log `/tmp/progress-build.log`. Isolated bundle `/tmp/DiscourseProgressc8.app`,
ID `org.discourse.native.progressc8`, scheme `discourse-progressc8`, display name
`Discourse Progress c8`. Main checkout build and running real app are untouched.
`codesign --verify --deep --strict /tmp/DiscourseProgressc8.app` passed after
ad-hoc signing; `/tmp/progress-sign.log` contains identity/signature output.
Source snapshot and copied App.framework payload equality passed before signing;
ignored `build/progress-review/source-before-build.json` and
`payload-equality.json` retain the fingerprints. Final trace details are in
native-manifest.json alongside this document.

Kernel SHA256: `2d7c551c75496b96ea3407a6ba187689116f64f8c11574d2e950433cbb033034`.

No CUA/browser/native inspection, screenshot comparison, iOS/Linux device run,
or spoken VoiceOver test has occurred. Keep in_progress / awaiting_slot; this
checkpoint is not review_ready or mergeable.

## Pinned-main integration follow-up

Merged coordinator-pinned `e612ad7b47413fa890b35ae3b55a6f6d37b08cf7` in
`a2984ddb589533370262b77270dab688e8b0a4bc`. All non-Progress rows match that
pinned main exactly. Preserved merged Button, Badge, Input, Radio, Checkbox,
shared application fixes, and Progress adapters. Generic Progress source is
unchanged; no speculative visual correction was made. DButton controls now
use the final merged component, superseding the earlier baseline dependency note.

142 integration tests passed, seed 9092026 (`/tmp/progress-integration-tests.log`):
Progress/component examples/offline fixture, update accessibility, Assign view,
composer uploads, Event Card, Badge/Users pages, assignment sheet and Button
adoption. Root/full analysis passed (`/tmp/progress-integration-analysis.log`,
`/tmp/progress-integration-full-analysis.log`). Locked pub get passed; root
rewrote only shared_preferences_platform_interface's dependency classification,
which was restored to avoid unrelated lockfile churn. No pin/dependency changes.

The exclusive browser-only reference slot was released immediately after the
first official page navigation was denied: admin-enforced browser security
policy could not be verified. No retry, indirect workaround, native app action,
website theme change, computed browser geometry, or rendered comparison occurred.
The failed batched call may have created a blank task-owned tab before navigation;
its existence/cleanup could not be verified without another browser operation.
No tab was marked to persist; ordinary browser-session cleanup owns it. Native
access remains explicitly ungranted. Both reference and native gates are pending.

The refreshed r2 bundle uses restricted-free local debug entitlements (JIT,
unsigned executable memory, debug attachment, network client/server), without
APNs, application-identifier, team identity or provisioning entitlements. This
changes only the isolated review copy, never the real app or project signing.
See updated native-manifest.json for exact source and payload trace.

## Independent review and native acceptance 2026-09-09

Reviewer task `01a08558-73d7-7d01-9b97-39615e28df0e` merged the implementation
history into `codex/review-progress` and compared the rendered component with
the official Base UI/base-nova page in the approved in-app browser. The live
reference measured a 4px, fully rounded track; a 56% composed example measured
384x36 logical pixels with the track 32px below its root; and its indicator used
the documented 150ms cubic-bezier(0.4, 0, 0.2, 1) transition. Light and dark
reference renders were captured and agreed with the frozen registry source.

The exact-source isolated macOS fixture was launched and inspected. Basic and
label/value examples matched the reference structure and proportions; light,
dark and Forest palettes updated the semantic track/fill/text colors live.
The 360px, 200% text, RTL pass kept labels and localized Arabic values readable,
with the fill anchored to logical start. Unknown progress visibly moved in the
ordinary state and stayed at logical start with reduced motion. Native Tab focus
was visible on the controlled example and Return advanced the value. The real
ComposerUploadQueue advanced 25% to 75%; UpdateDownloadProgress advanced 25% to
50%; and EventUnavailableCard/BadgesPage correctly removed their loading strips
when toggled ready. Native accessibility kept labels, status text and adjacent
actions as independent nodes without adjustable actions on progress itself.

No Progress rendering or behavior defect was found. Acceptance changed only the
styleguide status/notes from baseline/pending to implemented. Nine component and
styleguide tests passed after that metadata correction; root and full-profile
analysis had already passed on the integrated review branch. A refreshed debug
bundle `/tmp/DiscourseProgressReview6adbb135.app` was built from source commit
`6adbb135b43143486345f7c3ffa81c4bcbf09430`, with bundle ID
`org.discourse.native.progress.6adbb135`, URL scheme
`discourse-progress-6adbb135`, kernel SHA256
`38e072176e4ed4538d3edea674b6044d6ad7eb7127dc7570edb9a5fb81318d7c` and
the same restricted-free local debug entitlements. Deep strict signature and
built/copy kernel equality passed. The metadata-only status correction did not
invalidate the completed component/native inspection. No iOS/Linux device or
spoken VoiceOver test was performed.
