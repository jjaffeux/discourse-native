# Radio Group implementation and independent review

## Final composition follow-up — 2026-09-09

The original Radio Group remains accepted at merge
`62e7d25adeb8c125faca2a6476cbb800660a2025` (implementation
`99126e23b169f72ffde2975adb1da77fd5f966cb`). This separate follow-up composes
Description, Choice Card, Fieldset, Disabled, Invalid and RTL with the accepted
DField family and Default with DLabel. Radio remains the sole selection,
keyboard and Form owner. The original evidence below is retained as history.

Current source candidate: `3169db0954aa8e387ec316d1414a5a0d0cb5a919`.
All 278 affected tests, root/full analysis, font-loaded composition exports and
the isolated macOS build pass. Fresh official-browser and native macOS review
accepted all seven final examples in light/dark, custom 360px/200% RTL and
reduced-motion previews, radio/card keyboard behavior, Form validation/reset,
and the real local-fake Poll, flag, change-owner and move-post surfaces. The
desktop lease is released. The follow-up is merged locally as
`1f3b73293a842e65a5b7675e99496322c7595589`; 52 affected integration tests and
final root/full analysis pass on the latest-main candidate, with inspected
Radio/Field/adopter behavior unchanged.

See [final-composition evidence](evidence/radio-group/final-compositions/README.md)
for source pins, bounded shared-owner corrections, geometry and limitations.

## Historical implementation and original acceptance record

The remaining sections preserve the original staged implementation and review.
Their pending-state statements are superseded by the final follow-up above.

Reference: frozen 2026-09-08 Radio Group catalogue entry, all documented sections
(Usage, Composition, Description, Choice Card, Fieldset, Disabled, Invalid, RTL).
The local registry and example source are preserved under `reference/radio-group/`;
the shared `reference/LICENSE.shadcn.md` applies.

Sources retrieved 2026-09-09:
- https://ui.shadcn.com/docs/components/base/radio-group
- https://ui.shadcn.com/r/styles/base-nova/radio-group.json
- https://ui.shadcn.com/code/apps/v4/registry/bases/base/examples/radio-group-example.tsx

The registry's old Base UI Markdown API link returned 404. The current API is
https://base-ui.com/react/components/radio (captured as `reference/radio-group/base-ui-radio.md`
from https://base-ui.com/react/components/radio.md). Flutter 3.47.2's actual
`RawRadio` and `RadioGroup` source was inspected for native focus, checked
semantics, arrow wrapping and RTL behavior. No browser/native app was opened.

| Reference source | Flutter logical metric / behavior |
| --- | --- |
| `size-4`, `border`, `rounded-full` | 16×16 circle, 1px border |
| indicator `size-2` | centered 8×8 primary-foreground circle |
| checked primary background/border | live DTokens.primary |
| focus `ring-3 ring-ring/50` | 3px outer spread, focusRing at 50% |
| invalid `ring-destructive/20`, dark `/40` | 3px spread at 20%/40%; dark unchecked border 50% |
| `border-input`, dark `bg-input/30` | colors.outlineVariant; multiply its existing alpha by 0.3 for dark fill |
| disabled opacity 50%, forbidden cursor | 50% entire associated item; no activation or traversal |
| label composition `gap-3` | 12px indicator/content gap; DLabel 14px/500/1 |
| root `gap-2` | explicit 8px gaps in reference examples; child layout remains caller-owned |
| CSS after inset x=12/y=8 | Desktop follows intrinsic labelled row bounds; 48×48 minimum only on native touch |

The host owns fonts, palette, radius and inherited text scale. Choice-card
presentation uses the captured FieldLabel/Field classes: 10px padding, a 1px
border, rounded-lg (base radius ×1), selected primary borders at 30% light/20%
dark and backgrounds at 5% light/10% dark. Native comparison is still required. There is no animated
transition in the registry; changes are immediate, including reduced motion.

Desktop labelled rows use intrinsic content height with a 16px indicator. The
whole associated row remains clickable; no extra desktop minimum increases row
pitch. Native touch platforms retain 48px minimum bounds. The browser's enlarged
pseudo-element area is not duplicated outside the desktop row.

## Public API and ownership

`DRadioGroup<T>` owns initial selection. `DRadioGroup<T>.controlled` reads the
parent's `groupValue`; callbacks are requests and a rejected request preserves
the accepted value in Form save/validation. Both expose initialValue,
onChanged, validator, onSaved, autovalidateMode, forceErrorText, enabled,
invalid and label/description slots. Reset requests initialValue; a controlled
parent may decline or accept later without diverging Form and visible state.

`DRadioGroupItem<T>` provides value, label, description, trailing,
semanticLabel, enabled, invalid, focusNode, autofocus, card and toggleable.
Use distinct values and the same generic type throughout a group. Label slots
are activated together and merge semantics; independent interactive links
belong outside them. Borrowed focus nodes survive removal/replacement.

Native RadioGroup owns one Tab entry, wrapping arrow selection, disabled-item
skipping, Space activation and RTL horizontal navigation. Poll opts into
`toggleable` to preserve withdrawal of an existing vote. This is a domain
adaptation, not the default radio behavior. Form reset never silently changes
an accepted controlled selection. The existing merged DLabel is composed;
Field is now accepted; the final composition follow-up above uses its public
owners. The original implementation did not introduce a substitute Field.

## Application audit

- `topic_move_posts.dart`: destination radios retain search, automatic sole-result
  selection, async ownership checks, chronological ordering and submission.
- `topic_change_owner.dart`: user radios retain avatar, username/name, search,
  disabled saving state, permission and account/target ownership checks.
- `post_flag_editor.dart`: associated reason rows replace nested InkWell/Radio
  focus owners; message requirements, legal confirmation and async save remain.
- `plugins/poll/poll_card.dart`: single-choice and numeric options use a real
  radio group. Immediate voting, withdrawal, async rollback, results/tallies,
  permissions and deadline disabling remain in PollCard.
- Shell and Chat recognize RawRadio as a focus owner so pane shortcuts cannot
  steal radio navigation. Focus ownership regression uses the actual component.

Retained: Poll multiselect remains Checkbox task-owned; ranked-choice remains
its web workflow; menu-item radios in choice_menu retain menu semantics and
belong to menu tasks. Existing generic Label examples using native controls
remain under their component owners. Input owns search fields in change-owner;
Button owns Poll actions. No dependencies, lockfiles, pins or runner sources
are changed.

## Review fixture

`tool/radio_group_review_main.dart` mounts real PostFlagEditor and PollCard,
opens the real owner/move dialogs through ShellController, and links to the
actual styleguide. Stores, authenticator and API are in-memory fakes; the site
is radio-review.invalid. Search `review` for two options; other terms produce
empty results. Light/dark, RTL, 200% text and simulated save-error controls are
local. No credentials or account data are read or written. Widget verification
checks the actual search results can be selected in both dialogs.

Native review remains **awaiting_slot**, not review_ready. No claim of rendered
visual parity, VoiceOver speech, iOS device or Linux device inspection is made.
The coordinator must inspect styleguide and all four migrated surfaces before
merge. Bundle provenance and final automated verification are recorded below.

## Captured source hashes (SHA256)

- `examples.tsx`: `abb4e0ca3f42884001666c790aa061c31f6e1ae01c1451d80ed8c6f699f55ea0`
- `radio-group.json`: `874b30662ba338d06362491b663cae9198281a4bc385b6be6425f2de442384d7`

## Final automated verification and bundle

- Source commit: `767e3d49b9d0c2807b42a28a19bafc9f2483d5b8`; tree `54784dc4837233044b568082ded1f7c5d1ca863c`.
- 157 focused tests passed (`test/d_radio_group_test.dart`, Poll, flag editor,
  move/owner ownership, flag ownership, keyboard navigation and Chat drawer),
  seed `9092026`; log `/tmp/radio-verified-tests.log`.
- Final Poll wrapper refinement and real-dialog fixture passed 35 tests, same
  seed; log `/tmp/radio-final-poll-fixture.log`. This keeps multiselect outside
  radio semantics. No full suite was run.
- Root/full locked pub get, final root/full analysis, touched-code formatting
  and diff whitespace checks passed. Lockfiles and SDK pin did not change.
- Committed-source macOS debug build: `flutter build macos --debug --no-pub
  --target tool/radio_group_review_main.dart`; log `/tmp/radio-committed-build.log`.
- Isolated bundle: `/private/tmp/discourse-radio-review-35591zqt/Radio Group Review.app`.
- Bundle ID `org.discourse.radio-group-review`; URL scheme `discourse-radio-group-review`.
- SHA256 kernel: `623a8ae4684b35c11408691b1c4d3eb88858123527091811845a267ef0bf6cda`.
- Source and copied bundle kernels match. 725 tracked library/fixture/support
  files byte-match the source commit. Subsequent commit changes documentation only.
- `codesign --verify --deep --strict --verbose=2` passed after ad-hoc signing.
  Only the copied bundle's display name, bundle ID and scheme were changed.
- Main checkout/build and running application were untouched. Bundle was not
  launched; native inspection remains awaiting the coordinator desktop slot.

## Read-only / required API follow-up

The current Base UI API documents group and individual Radio.Root readOnly
and required. Group `readOnly` defaults false. Nullable item `readOnly` inherits
the group, with either boolean overriding it. The group checks the effective
policy of the requested item before changing Form state or calling onChanged;
a null toggle request checks the selected item's policy. Pointer, keyboard and
semantic activation all reach that guard. Native arrows still move focus through
read-only options; selection changes only when the destination permits it.
Disabled options remain excluded from focus, unlike read-only options. A
controlled read-only group with a null callback remains focusable.

No opacity or border change is added for read-only: the registry has no special
read-only appearance. The cursor becomes ordinary rather than actionable,
and semantics exposes readOnly with enabled/focusable state retained. Native
RawRadio continues exposing its tap action, which becomes a guarded no-op for
read-only items; it does not dispatch user callbacks or change selection.

`required` and nullable item `required` expose required-state semantics. They
do not add hidden validation rules: pass the existing FormField `validator`
for required-value enforcement and localized errors. This deliberate Flutter
adaptation keeps application validation in Form rather than copying browser
constraint validation. The new example includes both the announcement and an
actual validator. Parent-driven controlled values, Form save and explicit reset
continue working while read-only; declined reset preserves accepted state.

Current API Markdown SHA256: `abd2d336d02fa7c04608c5ae1d21a903a447350e35b362e9770ff02d01e70dfd`.

### Follow-up verification and replacement review bundle

This supersedes the earlier review bundle for native inspection.

- Executable source commit `88400eed4c5d4c2215b2df534e7b419c0258b9b1`, tree `3f37a23737e6bbf8af3d2182db910cda90b20409`.
- 162 focused tests passed, seed 9092026; log `/tmp/radio-readonly-regression.log`.
- Final 15 component tests passed with semantic-action binding and keyboard
  override checks; `/tmp/radio-readonly-component-final.log`. Root/full analysis
  clean; formatting and diff checks pass. No dependency or lockfile changes.
- Committed-source macOS debug build passed; `/tmp/radio-readonly-build.log`.
- Bundle `/private/tmp/discourse-radio-readonly-review-l6gbqvk1/Radio Group Readonly Review.app`.
- ID `org.discourse.radio-group-readonly-review`; scheme `discourse-radio-group-readonly-review`.
- Kernel SHA256 `c8399e45e0d59311d1bcebfc6fbef08400b7d3e29fab55ad1d36f95ef5416af9`; copied and original kernels match.
- 725 library/fixture/support source files byte-match the source commit.
- Deep strict ad-hoc signature verification passes. Only copied bundle identity
  metadata changed. Main checkout/running app untouched; bundle not launched.
- Native status remains awaiting_slot. No rendered comparison or device/speech
  claims. The added Read-only and required example is in the actual styleguide
  linked by the production fixture.

## Field composition correction

Supporting source https://ui.shadcn.com/r/styles/base-nova/field.json and current
https://ui.shadcn.com/docs/components/base/radio-group.md are preserved beside
the radio source. They defined the original card presentation. The final
composition follow-up now delegates that surface to the accepted DField family.

- FieldLabel's direct Field child uses `p-2.5`: 10px plus the outer 1px border.
- `rounded-lg` is host base radius ×1, including zero/custom values.
- Checked borders use primary/30 (light) and primary/20 (dark); fills primary/5
  and primary/10. Hover uses muted/50 only when enabled. Focus is a 3px outer
  card ring at ring/50 and ring-colored border. The later browser comparison
  below corrects the initial inference that the inner radio ring is suppressed.
- Field horizontal composition uses an 8px gap, top alignment with FieldContent
  and a 1px radio top margin. FieldContent uses gap-0.5 (2px). FieldTitle inherits
  14px/500; live browser measurement below resolves its title leading to 20px.
  Description is 14px/400 with 1.5 leading.
- The exact Plus/Pro/Enterprise example selects Plus and uses max-w-sm (384px).
  Description composition selects Comfortable and uses the same content metrics.
- The plain Label composition retains its documented 12px gap and 14px/1 label.
- Source input uses colors.outlineVariant, distinct from tokens.border. Every
  color opacity modifier now multiplies existing alpha, including destructive
  borders/rings, focus rings, input fill, card selected states and hover.
- Existing transparent native hit bounds and their documented row-pitch
  adaptation remain. ReadOnly/required and controlled reset behavior is retained.

A translucent custom palette regression distinguishes input from border, checks
light/dark selected card alpha, hover alpha, 10px padding and proportional radius.
Browser and native comparison have not been performed for this correction.

- `field.json` SHA256 `586110f5563cbb5dc0929207ee34361f1349cf2f816465799c60b98821e4cedc`

- `current-radio-group.md` SHA256 `e00939e01c108da6492bdf9a3d9ccf34bbb284e3dce26260dcf44dc4ef4219f6`

### Latest source-corrected bundle (supersedes previous bundles)

- Source `9ece5376b01fad2157af34ca2dd7914ba833e880`; 163 focused tests pass with seed9092026,
  `/tmp/radio-field-regressions.log`; root/full analysis clean.
- Final macOS build passed: `/tmp/radio-field-build.log`.
- Bundle `/private/tmp/discourse-radio-field-review-a2j2_677/Radio Group Field Review.app`; ID `org.discourse.radio-group-field-review`;
  scheme `discourse-radio-group-field-review`.
- Kernel SHA256 `16336ff6c32757e9362121e5d6763a2e35e65d98df43ae4fed546aaf055e15b6`; copied/original kernels match.
- 725 library/fixture/support files byte-match source commit; deep strict
  ad-hoc signature verification passes. Subsequent metadata commit changes
  documentation only. Main app/build untouched.
- No browser/native actions or font-loaded exports performed in this slot.
  Awaiting serialized rendered comparison and native inspection; no parity claim.

## Browser comparison and font-loaded exports (2026-09-09)

The authorized browser slot is complete and released. The temporary reference
Chrome tab was closed, original dark theme restored, and no user tabs or viewport
overrides changed. Native desktop remained locked and no native app was launched.

Live official reference measurements correct two source-only inferences: both
inner radio and outer card show 3px focus rings, and card titles use 20px leading.
Card bounds are 384×65, inner Field 382×63 with 10px padding, content gap 2px,
radio 16×16 with 1px top offset. Descriptions use 21px leading. Fieldset headers
use 20px leading with an effective 2px description gap and 12px before items.
Default group measured 109.859375×64; description 264.0859375×142.75;
fieldset group 320×73.75; RTL group 232.0546875×142.75.

Examples now match reference initial selections and widths: Comfortable for
Default/Description/RTL, Plus for cards, and Option2 for Disabled. Only the first
Disabled option is disabled. Native browser arrows skipped it; RTL Left advanced
to the next option and Space selected. Invalid labels are destructive and the
reference description sits above choices without an added bottom error message.

Focus rings now use outside foreground borders rather than BoxShadow, preventing
rings from darkening translucent interiors. A regression checks both rings,
outside stroke alignment, selected fill alpha, and card title leading.

See evidence/radio-group/README.md, the reproducible export harness, 22 PNGs and
SHA256 manifest. Widget exports include real flag/Poll and owner/move fixtures,
light/dark, custom palettes, RTL and 200% text. These are font-loaded test renders,
not native screenshots. Host SF/SF Arabic shaping differs from Geist/Noto Arabic;
host focusRing maps to primary; touch targets retain 48px minimum; desktop uses intrinsic row height. The live disabled radio span remains opacity 1 while its label dims;
our associated disabled row uniformly dims as previously documented. These
remaining differences are explicit adaptations, not claimed pixel parity.

### Desktop row geometry correction

Removed the discretionary 40×32 desktop minimum. Native RawRadio focus/semantics
remain, with 48×48 minima only on touch platforms. The associated desktop label
row is clickable at its intrinsic height. Re-exported all22 PNGs; measurements.json
records each row. Default is112.0094×64 versus browser109.8594×64;
Description272.2539×142 versus264.0859×142.75; Fieldset320×73 versus320×73.75.
Cards remain384×65. All inter-row gaps are8. The 0.75px total discrepancy is three
fractional19.25px lines resolving to19px with the loaded SF font; width differs
with SF versus Geist shaping. A regression checks intrinsic desktop row height,
Default64px total and8px gaps, alongside the existing48px touch checks.

Final focused impact suite:165 tests passed, seed9092026; `/tmp/radio-browser-regressions.log`. Font-loaded export run passed; root/full analyses checked separately.

### Latest browser-corrected review bundle (supersedes all previous bundles)

- Source commit `99126e23b169f72ffde2975adb1da77fd5f966cb`. Root/full static analysis clean;
  formatting and diff checks pass. 165 focused tests passed with seed 9092026.
- Committed-source macOS debug build passed; `/tmp/radio-browser-build.log`.
- Bundle `/private/tmp/discourse-radio-browser-review-zpdismeb/Radio Group Browser Review.app`.
- ID `org.discourse.radio-group-browser-review`; scheme `discourse-radio-group-browser-review`.
- Kernel SHA256 `2f72ac9df88df5dd329edafa55d2dced9a1c5e8961564768713b00484914ad11`; original/copied kernels match.
- 725 library/fixture/support files byte-match the source commit. Deep strict
  ad-hoc signature verification passes; only copied bundle identity changed.
- Main checkout/build and running app untouched. Bundle not launched.
  Native inspection remains awaiting_slot. This provenance update changes docs only.

## Native review completed

See evidence/radio-group/native-review.md and18 native screenshots. Component and production fixture inspection passed; no component defect found. Desktop slot released and isolated app quit. Styleguide marked implemented; progress review_ready for coordinator reconciliation. Native source remains99126e23; final change only updates status/notes and evidence. VoiceOver/device and old styleguide-shell AX limits remain explicit.
