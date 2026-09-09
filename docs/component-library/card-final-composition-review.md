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

Flutter shares one local submission callback between the Login button and the
password editor's Done/Return action. Email's Next action focuses Password.
The actual `Form` remains the validation owner. Associated labels override
Field's leading to preserve the frozen Label's 14px line height. The report
list retains the original Lucide/Feather chevron path and 2px top inset (source:
https://raw.githubusercontent.com/lucide-icons/lucide/main/icons/chevron-right.svg;
license: `reference/empty/LICENSE.lucide`). No production account or networking
surface was added.

## Source and automated verification

Reviewed source commit: `64b096856b682621b1c6f5cb17ac1f7a376abdd4`.
Only the Card example source and its focused widget tests changed. The seven
passive widgets in `d_card.dart` and every application adopter remain byte
identical to accepted main.

- 115 Card/Button/Input/Badge/Toggle Group/Field component and example tests
  passed with randomized seed `9082026`.
- Card's wider affected consumer run reached 200 passing cases. Two unchanged
  current-main failures remain outside this follow-up: the Button adoption
  inventory expects two Event Calendar constructions but finds one, and the
  Voice diagnostics export test does not observe `Voice report saved`. Neither
  involved a file changed here; the complete log is
  `/private/tmp/card-final-composition-impact.log`.
- Root and `profiles/full` locked dependency resolution passed without lockfile
  changes. Root and full-profile `flutter analyze --no-pub` passed.
- Formatting and `git diff --check` passed. Widget regressions verify local
  validation/submission, final owner types and variants, spacing selection and
  draft retention, plus stable editor element/controller/selection/focus across
  narrow, dark, 200% text and RTL reflow.

## Exact-source macOS fixture

`flutter build macos --debug --no-pub -t lib/styleguide_main.dart` succeeded
from source `64b09685`. The isolated copy is
`/private/tmp/CardCompositionReview-64b09685.app`, identifier
`org.discourse.native.card-composition.64b09685`, display name
**Card Composition Review**, and URL scheme
`discourse-card-composition-64b09685`.

The build and isolated copy have matching `kernel_blob.bin` SHA-256
`33a11a529025b74ec2c51f9bce86e5a8d32ebada1d5748afa2708b95934f699d`.
Deep strict ad-hoc signature verification passed. Signed entitlement read-back
contains only sandbox, JIT, local file selection, audio/camera, debug and
network client/server capabilities; it contains no application/team/APNs
identity.

## Rendered and native acceptance

Pending the canonical FIFO desktop lease.
