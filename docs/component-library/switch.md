# Switch implementation and review record

Status: implementation in progress; browser comparison completed; native inspection awaits the
coordinator's desktop slot. No native visual parity is claimed.

## Preserved official sources

Captured 2026-09-09; the documentation matches the frozen 2026-09-08 hash.
The snapshots live in `reference/switch/` and retain the upstream shadcn MIT
license in `reference/LICENSE.shadcn.md`.

| Source | SHA256 |
| --- | --- |
| https://ui.shadcn.com/docs/components/base/switch.md | `55cd0548461c68b00f0757af2f9617621542da29a000405f05878125782c450c` |
| https://ui.shadcn.com/r/styles/base-nova/switch.json | `1f22350ccbf358a3aa198305c41d91e146abc0a7d5b18a9a23488b8d6b264ab4` |
| https://ui.shadcn.com/r/styles/base-nova/field.json | `586110f5563cbb5dc0929207ee34361f1349cf2f816465799c60b98821e4cedc` |
| https://base-ui.com/react/components/switch.md | `d91041247b3af008bffb070f95f307f1e7cb87982c835b04a4fcb8fcecf4397a` |

## Source-to-Flutter mapping

| Reference CSS at 16px root / 100% scale | Flutter logical pixels |
| --- | --- |
| default w32 h18.4, thumb size-4 | 32 × 18.4 track, 16 × 16 thumb |
| sm w24 h14, thumb size-3 | 24 × 14 track, 12 × 12 thumb |
| border transparent, rounded-full | 1px border, fully rounded track, circular thumb |
| translate-x calc(100%-2px) | 14px default / 10px small directional travel; start/end swap in RTL |
| primary checked, input unchecked | DTokens.primary / colors.outlineVariant (input); dark unchecked alpha multiplied by .8 |
| background thumb; dark checked primary-foreground, dark unchecked foreground | corresponding live DTokens colors |
| focus border-ring and ring-3 ring/50 | 1px focus border and 3px outer ring at .5 opacity |
| invalid destructive border/ring | 1px border, 3px ring .2 light / .4 dark; dark border .5 |
| disabled opacity-50 | one .5 opacity owner, including associated label; no duplicate dimming |
| transition-all / transition-transform | 150ms cubic(.4,0,.2,1); zero duration with disableAnimations |
| Field gap-2, FieldContent gap-.5 | 8px horizontal gap, 2px title/description gap; description compositions align at top |
| FieldLabel leading-snug, text-sm medium; card FieldTitle | Ordinary 14px / 19.25px / w500; choice-card title 14px / 20px / w500, using host family and inherited scaler |
| FieldDescription text-sm leading-normal | 14px / 21px, muted foreground, wrapping |
| Choice card border, p-2.5, rounded-lg | 1px border + 10px inset, base radius token (rounded-lg ×1) |
| Choice card selected border/background | primary .3/.05 light, .2/.1 dark; hover muted .5 |
| Choice card current computed focus CSS | 3px wrapper and switch rings; current CSS specificity retains both despite the registry suppression utility |
| FieldGroup gap-5 | 20px between reference choice cards |

## Public API and adaptations

`DSwitch` supports controlled `value`/`onChanged`, or locally owned
`initialValue`, plus size, enabled, readOnly, invalid, autofocus, borrowed focus
node, accessible name and hint. `DSwitchTile` associates title and subtitle with
one row action and tab stop. `leading` supports the reference Airplane Mode
composition; the default trailing control accommodates app settings.
`choiceCard` is a switch composition, not an implementation of the pending
catalogue Field component. Existing merged DLabel provides label typography.

`DSwitchFormField` uses Flutter Form validation/save/reset. Controlled edits and
reset requests do not become accepted field values until the parent updates
`value`; reset rejection and deferred acceptance have explicit tests. A reset
requests the declared initial value through onChanged. Uncontrolled fields own
that transition immediately. Errors expose invalid semantics and a live region.

The browser hit extension is 12px horizontally and 8px vertically; native
standalone controls use transparent 48×48 bounds. Rows have intrinsic desktop
heights and a 48px minimum on Android/iOS/Fuchsia. Artwork is never scaled to achieve that target. Choice-card focus encloses
the clickable card and its switch, matching the measured live CSS. Flutter FocusableActionDetector, Actions, Shortcuts,
GestureDetector and Semantics own interaction; there is no Material/Cupertino
switch artwork or platform-dependent shape. Space and Enter toggle. Native text
wrapping replaces CSS text balancing; inherited text scaling remains the sole
scaler. Drag-to-toggle is not an exposed feature of the Base UI reference.

## Adoption

All actual stock switches under `lib/` were replaced. Callbacks, guards and
async ownership remain in their production owners:

- Settings GIF-animation persistence, Preferences linked-post notifications,
  group management membership/interaction/SMTP/unknown-sender settings.
- Chat mute/threading settings; explicit accessible names were added to the
  standalone actions. Shell and Chat keyboard navigation guards recognize
  DSwitch and DSwitchTile so pane shortcuts do not steal switch key presses.
- Poll public/automatic-close settings; local-date time/range settings.
- Voice room push-to-talk/status, editor public/stage/video/LiveKit, and
  diagnostics capture. Slider controls were left to their assigned task.
- AI proofreading uses the small artwork. Its existing outer semantic/action
  owner remains; the nested artwork excludes focus/pointer/semantics, removing
  the previous scaled native switch while retaining the real setting callback.
- Label, Spinner and Separator interactive example switches now use DSwitchTile.
  Checkbox examples and the Spinner busy badge remain with their assigned owners.

Retained alternatives: Flutter switch type checks remain in keyboard guards
for compatibility with external callers. DLabel's old native list-tile
association tests still cover that supported use; they do not render the library
styleguide or production switches. Other control families remain out of scope.

## Verification and review fixtures

Focused checks, final commit and isolated build trace are recorded in the Switch
row of progress.json. The full test suite is intentionally not run, per user
policy. No SDK, dependency or lockfile change is part of this work.

`tool/switch_review_main.dart` mounts the actual production Settings,
Preferences, Chat channel settings, Poll, local-date, group-management and Voice
diagnostics widgets using memory stores, fake API/authentication and local
callbacks. It also opens the complete styleguide with its independent theme,
viewport, direction, text-scale and reduced-motion controls. Fake Voice capture
never starts real microphone, networking or diagnostics capture. Group saves
report their local submitted payload; export previews stay in the fixture.
The fixture does not start the real application or inspect real accounts.

Browser comparison of Switch examples is recorded below. Native inspection of
Switch and representative migrated surfaces remains pending. Additional Voice room/editor and AI composer native fixture
coverage may be extended during the review slot; their actual-widget regression
suites run now. No iOS/Linux device or spoken VoiceOver verification is claimed.

## Isolated macOS bundle

Source commit: `9ab5a887cbf71b021022454f91cbdcd8f6041a4b`.
Build: `flutter build macos --debug --no-pub -t tool/switch_review_main.dart`.
Bundle: `/private/tmp/discourse-switch-review-9ab5a887/Discourse Switch Review.app`.
The original worktree build and isolated bundle have the same kernel SHA256:
`4545ebfacea1b7417d4f2e5820a2fa1a2be8c2714f208b015b608b5ff0df7d59`.

The copy has bundle ID `org.discourse.switch-review` and URL scheme
`discourse-switch-review`; `codesign --verify --deep --strict --verbose=2`
passed after ad-hoc signing. Only the isolated copy removes the APS entitlement.
Workspace runner configuration and the user's main-checkout app were preserved.
The full trace, source equality and source hash are recorded in
[switch-review-build.json](switch-review-build.json). This bundle has **not been
launched or natively inspected**; it is queued for the serialized desktop slot.

## Source fidelity correction — 2026-09-09

The [official theme scale](https://ui.shadcn.com/docs/theming#radius-scale)
uses the base radius for rounded-lg; choice cards now follow it directly,
including live custom radius changes (0, 6 and 18px tested). Source `input`
maps separately to `DTokens.colors.outlineVariant`; `border` remains
`DTokens.border` for the unselected choice-card border.

All Switch CSS opacity modifiers now multiply the existing token alpha:
unchecked dark input ×.8; destructive borders/rings; focus rings; selected
choice-card borders/backgrounds; and hover muted backgrounds. Focus borders,
checked tracks and unmodified colors retain the source alpha unchanged.
Tests deliberately separate input and border and use translucent tokens to
prevent opaque default palettes from masking these distinctions. Controlled
Form/reset behavior and all production callbacks are unchanged.

## Browser-only comparison — 2026-09-09

The coordinator granted an exclusive Chrome slot. Official Switch previews were
captured in light and dark, with measured default/small tracks and thumbs,
description and choice-card compositions, invalid and RTL states. Small Space
travel was 10px, Enter returned it to unchecked, and RTL Space travel was -14px.
Default reference height is 18.3984375 CSS pixels (browser subpixel quantization)
versus Flutter's declared 18.4 logical pixels. Choice cards measure 384×86px,
including 14/20px FieldTitle leading, 2px content gap and 10px inset + 1px border.
Invalid description text stays muted; title, border and ring signal the error.
The current site renders both wrapper and track focus rings inside choice cards;
the implementation now follows that observed result.

Compared saved official previews with final font-loaded actual-widget exports.
Checked light primary was observed as black and corrected in the neutral export
adapter. Dark input is white at .15 alpha, multiplied by .8 to .12. Actual source
`border` is white at .1 alpha. Custom Forest/Plum exports at 360px/200% RTL showed
wrapping and preserved compact artwork with square/18px-radius choice cards.
Size examples center and associate each clickable label. Intrinsic desktop
rows plus the source 20px gap give approximately 39px center spacing. Touch
platforms retain 48px row targets.

Evidence and renderer/source hashes are in `evidence/switch/`. CSSOM stylesheet
rules were not exposed by the read-only browser bridge (zero rules returned);
actual DOM classes, computed values, saved registry source and screenshots are
preserved instead, together with SHA256 hashes of all four observed immutable
stylesheet URLs fetched through read-only HTTP. No screenshot pixel-equality claim is made: browser Geist/
Noto Arabic and native SF/SF Arabic shaping differ, as do canvas pixel ratios.
The shared DTokens.focusRing maps to host primary; the official neutral focus
ring is an independent gray. This existing theme mapping remains explicit and
was not changed globally in this component correction.

The original website dark theme was restored, no viewport override was applied,
and the sole comparison tab was closed before releasing the slot. No native app
was launched or inspected. Native inspection remains awaiting_slot.


## Exterior-ring and compact-row correction

Reused committed primary browser screenshots/metrics and read main's updated
visual-fidelity.md on 2026-09-09. No CUA, browser or native app was launched.
Track and card rings now use animated foreground borders with a 3px exterior
stroke. They retain both browser-observed focus rings and do not paint behind
translucent input/card fills. Raster regressions sample unchanged interior RGBA
and changed exterior RGBA for normal/focused/invalid light/dark controls.

Desktop single-label rows follow their intrinsic text/indicator height (18.4px
for a leading standard switch); one-line descriptions are approximately 42px,
and a title-only card is 42px. Wrapped reference cards remain 384×86px. Tests
exercise macOS/Windows/Linux and Android/iOS 48px touch bounds, including row-edge
activation. Generic layouts have no desktop minimum. Poll and Group adapters
alone add 8px vertical padding: fixture renders exposed switch labels abutting
adjacent fields and descriptions after removing the global minimum.

Regenerated 20 component exports (including light/dark focused cards), plus 14
real local-data fixture exports. Inspected normal/invalid/focused light/dark,
Size spacing, Forest/Plum radius0/18 at 360px/200% RTL, and Settings, Preferences,
Chat, Poll, Local Date, Group and Voice fixture layouts. Existing font shaping
and shared focus-token limitations above still apply. These widget renders do
not satisfy the native inspection gate.

221 affected tests passed (seed 782312), followed by 59 component/fixture/export/
Poll/Group checks after the narrowly scoped adapter/Size spacing adjustment.
Logs: /private/tmp/switch-exterior-final-tests.log and
/private/tmp/switch-exterior-adapter-tests.log. Root/full analysis was rerun
following removal of the temporary export test. Native status stays awaiting_slot.
