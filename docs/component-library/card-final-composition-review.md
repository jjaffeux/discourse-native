# Card final composition review

This follow-up leaves the accepted seven-part Card API and application adopters
unchanged. It completes the frozen Card page's compositions after their shared
owners merged. The frozen Markdown was retrieved again on 2026-09-09 and its
SHA-256 remains
`718dec761e0ad426b53d4673d206ab6dbfbbff5757f9714b883a04126f75db3e`.

## Accepted owner reconciliation

- Button `eb6d8ea0d9417f0edc830c5ce715b52436f12c94`: primary form actions,
  outline secondary actions, link treatment, local activation and disabled
  policy.
- Input `7df72ef294826616e8ba24c31c6129d8e9041fec`: email/password editing,
  native keyboard type, obscuring, required state, Form validation and
  caller-owned controller/focus lifecycle.
- Label `9bbc2806020646451fd1c283d347283fe4e45f67` and Field
  `5cd7f3694498e4e09e3c114639baca834b56705e`: visible focus-activating labels
  and bounded control metadata matching the frozen `htmlFor` composition.
- Badge `916580e72e11de6a6b7872c41d5c4d92e27e9635`: secondary Featured status.
- Toggle Group `b77f25c9ac779f324dd3853590df0ce0dd27eaa9`: controlled outline small
  16/20/24/32px spacing choice with required selection and native roving focus.
  Card's narrow RTL preflight exposed off-screen keyboard focus. The owner
  corrected this in follow-up merge `aaff45d5af3456c3d44e0e681400a071cb673908`.
  The inspected fixture integrates prepared commit `68e29a31`; its component
  and test source exactly match accepted source `d1815e50`. Card's regression
  confirms End reveals 32px without selecting it, then Space selects it.

Flutter shares one local submission callback between the Login button and the
password editor's Done/Return action. Email's Next action focuses Password.
The actual `Form` remains the validation owner. Associated labels override
Field's leading to preserve the frozen Label's 14px line height. The report
list retains the original Lucide/Feather chevron path and 2px top inset (source:
https://raw.githubusercontent.com/lucide-icons/lucide/main/icons/chevron-right.svg;
license: `reference/empty/LICENSE.lucide`). No production account or networking
surface was added. The recovery anchor has measured inline text bounds rather
than a 32px padded Button row. Its 14px/20px normal-weight foreground label
wraps using the inherited scaler and available width, while the accepted
`DButton` retains native focus, hover underline, link semantics and activation.

## Source and automated verification

Reviewed source commit: `49e27ca655373749b9099325ac78f56b27313824`.
Only the Card example source and its focused widget tests changed. The seven
passive widgets in `d_card.dart` and every application adopter remain byte
identical to accepted main.

- 125 Card/Button/Input/Badge/Toggle Group/Field component and example tests,
  including Voice diagnostics, passed with randomized seed `9082026` after
  integrating both owner follow-ups.
- The combined owner/example/affected-consumer run on integrated source
  `2cbfd9fe` reached 304 passing cases and one failure: the Voice diagnostics
  export test did not observe `Voice report saved`. The earlier Calendar
  adoption inventory failure was
  resolved by main's `9834f36a` test correction. The subsequent inline-link
  change affects only Card examples and passed the 117-case owner/example run.
  Clean unchanged main `7b09b62d` reproduced the Voice assertion at
  `test/voice_diagnostics_view_test.dart:236` with seeds `9082026` and `14761`.
  Toast adoption `972690cf3` changed feedback to `DToast.show`; the test host
  omits `DToaster`, unlike production `DiscourseApp`. Adding only the production
  toast host in a temporary diagnostic checkout made all four tests pass with
  every clipboard, streaming export and success-message assertion unchanged.
  Evidence was sent to the accepted Toast reviewer
  `01a08592-b1eb-7ad2-bebb-3ddea00f2702` for its narrow follow-up. Logs are
  `/private/tmp/card-main-voice-baseline.log` and
  `/private/tmp/card-main-voice-toast-host.log`.
  The Toast reviewer merged the host correction as `0f9b7756`. All four Voice
  tests now pass in Card's integrated candidate, preserving every assertion.
- Root and `profiles/full` locked dependency resolution passed without lockfile
  changes. Root and full-profile `flutter analyze --no-pub` passed.
- Formatting and `git diff --check` passed. Widget regressions verify local
  validation/submission, final owner types and variants, spacing selection and
  draft retention, plus stable editor element/controller/selection/focus across
  narrow, dark, 200% text and RTL reflow.

## Exact-source macOS fixture

`flutter build macos --debug --no-pub -t lib/styleguide_main.dart` succeeded
from source `49e27ca6`. The isolated copy is
`/private/tmp/CardCompositionReview-49e27ca6.app`, identifier
`org.discourse.native.card-composition.49e27ca6`, display name
**Card Composition Review**, and URL scheme
`discourse-card-composition-49e27ca6`.

The build and isolated copy have matching `kernel_blob.bin` SHA-256
`7e5e09b5d7274a04332e50e23068fdf4c5e100109acd514c4bb44e513a7d34e6`.
Deep strict ad-hoc signature verification passed. Signed entitlement read-back
contains only sandbox, JIT, local file selection, audio/camera, debug and
network client/server capabilities; it contains no application/team/APNs
identity.

## Rendered and native acceptance

Pending the canonical FIFO desktop lease.
