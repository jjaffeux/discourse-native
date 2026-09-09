# Slider implementation and pending native review

Status: **in_progress / awaiting_slot**. Native desktop comparison has not run.
The source, tests and offline fixture are prepared in `codex/ui-slider`.

## Reference and metrics

Frozen scope: [Base Slider](https://ui.shadcn.com/docs/components/base/slider),
2026-09-08 catalogue: Range, Multiple Thumbs, Vertical, Controlled, Disabled,
and RTL. Documentation, official registry and example snapshots have their
URLs and SHA256 digests in [sources.json](references/slider/sources.json).
Official example source is pinned to upstream commit
`3ba91b1cc83e1bbe4ab35a422ff2a694849c5048`.

| Base-nova source | Flutter logical pixels at 1× |
| --- | --- |
| `h-1` / `w-1`, `rounded-full` | 4px track, fully rounded clip |
| `size-3`, `border`, `rounded-full` | 12px circular thumb, 1px focus-token border |
| `bg-white` | White thumb in both modes, explicitly required by registry |
| `ring-ring/50`, `ring-3` | 3px spread ring at 50% token alpha |
| `bg-muted`, `bg-primary` | Live `DTokens.muted` and `DTokens.primary` |
| `thumbAlignment="edge"` | Thumb centers travel from 6px to extent−6px |
| `data-disabled:opacity-50` | Entire control at 50%; no input/focus actions |
| `transition-[color,box-shadow]` | 150ms color/ring animation; zero with reduced motion |
| `after:-inset-2` | Native transparent 48px target, compared with reference 28px target |
| `max-w-xs` | Reference example width capped at 320px |
| Vertical `h-40`, `gap-6` | 160px extent, two 12px thumbs separated by 24px (36px centers) |
| Controlled Label / value | 14px label and muted value text, native text scaling |

The invisible native target is larger than the source target without enlarging
thumb or track artwork. Vertical example target boxes overlap their transparent
edges while keeping source-faithful thumb separation. White thumb is a
source-specific constant, not a hardcoded theme palette. Fonts inherit the app
family. Slider itself renders no text; labels and displayed values scale once.
Actual rendered comparison in light/dark/custom palettes is still required.

## API and interaction

`DSlider(value:, onChanged:)` uses a scalar; `DMultiSlider(values:, onChanged:)`
uses two ordered values for a range and any positive count for multiple thumbs.
`DSliderField` and `DMultiSliderField` supply Form validation, save/reset, initial
values and optional externally controlled values. Null callbacks disable direct
sliders. Form fields use `enabled` and own state when external values are omitted.
The caller owns borrowed focus nodes; the component disposes only owned nodes.

Values must be finite, ordered, in bounds and meet `minStepsBetweenValues`.
Bounds may be equal, producing a disabled fixed-value control. A positive `step`
snaps proposals relative to `min`; `step:null` supplies continuous pointer input
and a keyboard increment of 1% of the range. Off-grid controlled values are
accepted for live playback and custom site geometry. A final non-divisible
endpoint is clamped to the bound. Decimal step arithmetic is normalized to 15
significant digits before callbacks. `largeStep` defaults to an absolute 10 units, matching Base UI; an explicit
value overrides it. Both Form field adapters expose this option.

Every thumb is a Tab stop with an individual semantic name/value/increase/
decrease action. Arrows move one step; Shift+arrows and Page keys move a large
step; Home/End move to legal bounds. Horizontal RTL reverses left/right;
vertical increases upward. Keyboard movement stops at neighbours. Pointer
movement pushes neighbours by default, matching Base UI. The `swap` policy
moves the dragged value into its nearest legal insertion interval without
changing other values; `none` clamps at neighbours (`stop` is a compatibility
alias). Minimum spacing remains valid even while crossing several thumbs.

Labels and borrowed focus nodes describe sorted slots. When a parent accepts
a swap, including clamping only the dragged value, focus follows that value to
its accepted slot. Rejected proposals do not move focus or visible values. If
the parent replaces several values at once, the numeric list supplies no stable
value identity; the active sorted slot is retained rather than guessed. Tab and
semantic order explicitly follow sorted slots in both RTL and vertical layouts.
Equal thumbs can separate in either direction: drag selects the outer thumb
in that direction, and keyboard accesses each thumb. DMultiSliderField exposes
the same collision policies.

Pointer capture accepts a single primary pointer, supports track jumps, retains
capture outside bounds and cancels on pointer cancellation or Escape. The
slider claims the gesture (matching reference `touch-none`) so dragging does not
also scroll its enclosing pane. Bounds/step/orientation/spacing/thumb count/
focus-node/collision-policy changes invalidate capture. Removal safely ignores
remaining captured pointer events; it does not invoke callbacks on disposed
callers. Configure a finite width inside intrinsic layouts such as AlertDialog;
the Voice adapter supplies 280×48 bounds.

Controlled parent values always own painting and semantics, including during a
drag. Rejected proposals do not appear; clamped or external updates render on
the next parent frame. `onChangeStart` gets the accepted starting values;
`onChanged` receives immutable proposals; `onChangeEnd` runs after the next
parent frame and reports accepted values. Configuration change or removal
suppresses pending commits. This native lifecycle callback also completes an
unchanged accepted interaction, so callers can finish interaction cleanup.
It intentionally differs from Base UI `onValueCommitted`, which fires only
for accepted changes. Cancellation does not undo changes already accepted
by a caller, and invokes only `onChangeCancel`. Controlled Form fields mark
interaction without storing rejected proposals; save/reset use the supplied
value. Uncontrolled fields reset to their initial value.

`secondaryTrackValue` is an optional buffered seek position painted below the
active input range at 35% primary alpha. It is a native playback adaptation of
the former Material secondary track, not a separate Progress component.

## Adoption

- `inline_video.dart`: actual playback timeline uses DSlider and preserves
  live position/duration/buffer, duration-zero disabling and millisecond seek
  callbacks. Since its units are milliseconds, it explicitly sets largeStep to
  10% of duration for useful Page-key seeking; the library default remains 10
  units. Playback ownership and asynchronous session behavior are unchanged.
- `topic_progress.dart`: TopicPositionSlider sends integer post selection;
  the existing editor owns navigation, busy guards and route/lifecycle checks.
- `voice_room_view.dart`: VoiceParticipantVolumeSlider sends 0–1 volume in 0.1
  steps. Dialog retains local state and existing persistence/media callbacks.
  Switch task owns adjacent Voice switches; merge only the volume hunks here.
- Skeleton and Aspect Ratio examples use DSlider for geometry controls;
  preserve their discrete or continuous domain steps and semantic formatting.
- `keyboard_navigation.dart` and Chat `chat_drawer.dart` recognize DMultiSlider
  as keyboard-owning input, preserving native reading/chat shortcuts around it.

Retained: read-only topic/media progress is not input and belongs to Progress;
resizable-pane and Chat viewport slider semantics describe distinct interactions,
not value-selection controls. Material Slider/RangeSlider type guards remain
for external/compatibility consumers. No other concrete Material Slider controls
remain in core/bundled plugin source after this migration.

## Review fixture and verification

`tool/slider_review_main.dart` mounts real production TopicPositionSlider,
VoiceParticipantVolumeSlider and InlineVideoPlaybackSurface with a local fake
session. Buttons control theme, RTL, 2× text, disable/removal and external
playback updates; Styleguide opens the actual component catalogue. No media
account, credentials, network or platform playback is used. Fixture tests
exercise seeking, disable/removal/restoration and topic keyboard ownership.

Focused tests cover capture/cancellation/removal, keyboard/RTL/vertical,
overlapping thumbs, collision spacing, per-thumb semantics, controlled
rejection/clamping/external updates, Form save/reset, borrowed-node lifecycle,
geometry, large text, actual styleguide examples and migrated production input.
The existing video, topic lifecycle, Voice, reading keyboard, Chat drawer and
Skeleton/Aspect Ratio example suites are included. Root and full-profile analysis
and enforced lockfiles are checked without changing dependencies or Flutter
3.47.2. The full application test suite is deliberately not run.

No native, browser-rendered, iOS/Linux device, or VoiceOver speech verification
has occurred. The task must remain in_progress until the coordinator grants a
desktop slot and both native production fixtures and reference comparisons pass.
Bundle identity, source/kernel hashes and final command outcomes will be recorded
in the progress row and native evidence record after the isolated build.

## Prepared bundle

Final executable source: `3813f11df01e4a1db8d7b45fe0457d8f904f4d49`.
[Native preparation evidence](evidence/slider/native-preparation.json) records
source equality, tree IDs, Credits stamp, kernel hashes and signature output.
Bundle: `/private/tmp/DiscourseSliderReview-01a083ce.app`.
Identifier: `org.discourse.native.slider.01a083ce`.
URL scheme: `discourse-slider-review-01a083ce`.
The source/copy kernel SHA256 is
`1aae7dca646a7e21939f7c334e1fc16d29412d9a8869651b977b61baa0dbd6a0`.
Deep strict ad-hoc signature verification passed. Only the isolated copy's
identity and signature were changed; its fixture entitlements omit push.
The main checkout's application and build directory were untouched.

The 217-test focused selection passed; after the final frame scheduling
safeguard, all 14 Slider interaction/controlled tests passed again. Final source
root and profiles/full analysis report no issues. See
[verification output](evidence/slider/verification.txt). The bundle is **not
launched** and remains queued for native inspection.
