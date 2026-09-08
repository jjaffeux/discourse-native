# Spinner native inspection evidence

Inspection used the coordinator's exclusive desktop slot on 2026-09-08,
macOS 26.6.2 (darwin-arm64), with Flutter 3.47.2. Apps were isolated ad-hoc
builds; no repository runner, SDK, pin, lockfile, global accessibility setting
or authenticated account was changed.

## App identities

| App | Bundle identifier | Artifact |
| --- | --- | --- |
| Initial implementation | `org.discourse.native.styleguide.spinner` | `/private/tmp/discourse-ui-spinner-native/build/macos/Build/Products/Debug/Spinner Styleguide.app` |
| Baseline comparison | `org.discourse.native.styleguide.spinner.baseline` | `/private/tmp/discourse-ui-spinner-native/build/macos/Build/Products/Debug/Spinner Baseline.app` |
| Reference SVG implementation | `org.discourse.native.styleguide.spinner.fidelity` | `/private/tmp/discourse-ui-spinner-fidelity/build/macos/Build/Products/Debug/Spinner Fidelity.app` |

The comparison restores byte-identical `5fd6658b` versions of
UserMenuMessage, GifPicker and DButton. A bare Cupertino/Material indicator
shim preserves the example constructor API without the new DSpinner semantics,
focus/input exclusion or lifecycle wrappers. The temporary fixture mounts the
actual core and GIF widgets with local gated data; GIF height is its native
540px maximum. It makes no account requests.

## Forced-semantics comparison

Both diagnostic apps add the same temporary
`WidgetsBinding.instance.ensureSemantics()` call after binding initialization.
From Size and customization, select Plum, 360px, 200% text, RTL and reduced
motion, then switch to Migration fixtures.

The initial implementation crashed at that transition. The baseline repeated
the crash on 2026-09-08 at 22:09:22 +0200, before the final SVG app was opened.
Both reports show SIGSEGV / EXC_BAD_ACCESS at `0x48` with these leading frames:

1. `flutter::AccessibilityBridge::CreateRemoveReparentedNodesUpdate()`
2. `flutter::AccessibilityBridge::CommitUpdates()`
3. `-[FlutterViewController updateSemantics:]`

The original report is preserved at
`build/component-library/spinner-native/new-spinner-forced-semantics-crash.ips`.
The baseline report is preserved at
`build/component-library/spinner-native/baseline-forced-semantics-crash.ips`,
SHA-256 `109d039d154e65ce4cc92f8a8cad45fa2e6cc9467d0b7e8b0af4691ddc6e2a17`.
These are ignored local diagnostic artifacts. Global CUA state confirmed the
baseline app absent after the crash.

This bounded comparison establishes that the new DSpinner implementation is
not necessary to trigger this diagnostic crash. It does not identify the
underlying framework/fixture cause. Production and final SVG entrypoints do
not contain the forced-semantics diagnostic.

## Normal-lifecycle SVG inspection

The source-matched SVG app completed the following checks without a crash:

- Current dark and Light: exact arc at 12/16/24/32px, radial custom artwork,
  accent color, 32px selection and pause; live palette changes retained state.
- Light: reference default/outline/secondary disabled loading buttons; actual
  DButton loading, visible Tab focus on Complete operation, and Return completion.
- Light: 12px badge artwork in primary/secondary/outline pills, leading/trailing
  placement, then completion removing the indicators.
- Light: inline/block input loading; accepted editing; typed subject/message;
  validation, rejection, retry, acceptance and local send with retained text.
- Light: empty-state media, title/description and cancellation; failure/retry
  and completion replace the busy state.
- Forest: payment composition at normal size and at 360px, 200% text, RTL and
  reduced motion. Large labels wrapped and logical placement followed direction.
- Plum, 360px, 200% text, RTL, reduced motion: actual UserMenuMessage loading,
  failure, Retry, loading, completion to No unread notifications; actual GifPicker
  loading, error, Try again, loading, completion to empty search instructions.
  The same fixture transition remained stable with normal semantics lifecycle.

Native AX exposed text fields and popup menu labels, not Spinner status nodes.
Widget semantics tests pass; native spoken VoiceOver output is unverified.
No iOS or Linux device execution was performed.

## Final example corrections

Native inspection found three local sample details to correct: an error shadow
showing through the transparent input interior; unused payment-row flex space
that shortened its title; and stale waiting instructions after request completion.
The input now fills its interior with the theme background. The payment amount
uses its intrinsic width with a half-row cap for narrow/large-text cases. The
empty description now follows busy versus finished state.

All 13 focused example tests pass (seed `2614942230`), including the new payment
end-alignment regression, and root analysis is clean. The refreshed isolated
build succeeded and matches the final example source.

## Relaunch keyboard incident

On the first relaunch for those corrections, after typing the Spinner search
and opening the Theme menu, the preview stopped responding to selection and
Escape. This was not another crash. The verified isolated process was PID 13780,
using 97.6% CPU, with no Spinner Fidelity crash report. A one-second passive
sample taken at 22:36:03 +0200 showed repeated main-thread activity through
FlutterKeyboardManager processNextEvent, FlutterEmbedderKeyResponder,
FlutterChannelKeyResponder and Flutter message callbacks. The source/tooling
cause has not been established.

The sample is preserved at
`build/component-library/spinner-native/fidelity-menu-keyboard-loop.sample.txt`,
SHA-256 `7fc2c30a768983cea7dd552c4f042f98fae0b80c8c4d6fcd0e2a0020ef8887fd`.
The app quit through its own native menu. A subsequent global CUA snapshot
confirmed both Spinner bundle identifiers absent, and the slot was released to
the coordinator for Label. The app stayed closed until the coordinator granted
the bounded reinspection below.

## Final bounded reinspection

After the follow-up slot grant, the already rebuilt, source-matched Spinner
Fidelity app passed the three remaining corrections using pointer-only
navigation:

- Light input rejection: the red error ring stayed outside the white textarea
  interior, and the validation error remained readable below the field.
- Light empty state: both Cancel request and Complete request replaced the
  waiting description with "Your sample data is unchanged. Start a request to
  try again." The appropriate canceled/completed title and Start request action
  were visible.
- Light payment row: at Fit/100%/LTR the full "Processing payment..." title and
  amount were visible, with the amount at the inline end. At 360px/200%/RTL the
  amount occupied the left inline end, the spinner the right logical start,
  and the Arabic title wrapped without overflow.

No crash or unresponsive episode occurred during this bounded pass. Pointer-only
success does not establish a cause or fix for the earlier keyboard event loop.
The preceding full SVG examples and actual core/GIF fixture evidence remains
valid; neither the baseline diagnostic nor those complete sequences was repeated.

Only the isolated Spinner app was quit through its native menu. A subsequent
global `cua.getState()` snapshot confirmed all three Spinner bundle identifiers
absent, and the desktop slot was released to the coordinator for Avatar.
Implementation and native correction verification are complete; device and
VoiceOver limitations above, and the unassigned keyboard incident, remain
explicit.
