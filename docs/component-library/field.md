# Field implementation and independent review

## Independent acceptance — 2026-09-09

Field is accepted. This section supersedes the historical preparation and
`awaiting_slot` statements retained below. The independent reviewer reconciled
the implementation with the accepted Input, Textarea, Checkbox, Radio Group,
Switch, Slider, Native Select, Button and Dialog owners, fixed disabled choice
cards so opacity applies to the complete bordered surface, and verified the
result from source `4efec6cc` in an exact isolated macOS bundle.

The official rendered Base UI page was inspected in the approved browser in
both light and dark themes. The 448px field group, 8/20/12px field/group/choice
rhythms, 320×65 choice card, 10px radius, 14px/19.25px medium choice label,
selected alpha treatment, responsive row layout and the complete set of
payment, editor, select, slider, fieldset, checkbox, radio, switch, choice,
group, RTL and error compositions matched the captured source mapping.

The exact native bundle passed light/dark, LTR/RTL and 100%/200% inspection.
Choice-card pointer selection worked, the disabled card stayed inert and the
entire surface dimmed, responsive content reflowed without overflow, and empty
submission exposed the expected invalid label, border and message. The actual
styleguide payment and editor examples exposed one editable/select owner each;
the real Preferences page exposed one Native Select and one Switch owner; the
real Voice editor exposed direct DInput/DTextarea/DSwitchTile/DNativeSelect
owners. VoiceOver speech was not run, so screen-reader behavior is supported by
widget semantics tests rather than claimed manual speech output.

Public composition contract: DField owns layout and metadata only. DInput,
DTextarea, DCheckbox, DRadioGroup, DSwitch/DSwitchTile, DSlider/DMultiSlider,
DNativeSelect and DButton retain value, Form, validation, focus and action
ownership. DFieldControl wraps one otherwise-unlabelled native/custom control;
do not add it around a public control that already owns those semantics. The
responsive custom-error example deliberately retains one native
FormField/TextField because DInput has no custom error builder.

## Radio final-composition intrinsic sizing correction — 2026-09-09

The Field owner approved the bounded shared change carried by Radio review
source `28418a2d`: fixed horizontal/vertical DField orientations build their
existing Flex directly, supporting IntrinsicWidth. Only responsive orientation
uses LayoutBuilder. DFieldGroup's group-width contract and DFieldSet's generic
spacing remain unchanged. New horizontal/vertical intrinsic tests and the
existing responsive editing, focus and Form-reset regression pass.

Radio's frozen 2px legend/description header is explicitly composed with
DFieldContent, not a change to generic FieldSet sibling spacing. Original Field
acceptance and owner pins remain intact. See
[Radio final-composition evidence](evidence/radio-group/final-compositions/README.md)
for the follow-up's acceptance status.
The correction is accepted and merged through Radio final-composition merge
`1f3b73293a842e65a5b7675e99496322c7595589`.

## Historical implementation record

The remaining sections preserve the original implementation and staged
integration evidence. Their status/dependency wording is historical.

Branch `codex/ui-field`, base `402fe578`. Field was **in_progress**;
styleguide status is baseline until reference/native review and dependent-control
reconciliation. No desktop/browser slot was used. See its progress row for checks
and build evidence.

## Pinned-main integration preparation

The coordinator requested a bounded integration of pinned main
`e612ad7b47413fa890b35ae3b55a6f6d37b08cf7`. Merge `6c31531c` retains every
non-Field progress row and shared root fix from that exact main. Only the public
barrel conflicted; it retains both Field and Input. The sections below preserve
the original reference/implementation history; this section supersedes their
statements that Button, Input, Radio and Checkbox are unmerged.

- Ordinary single-line Field examples now use merged DInput. DCheckbox uses its
  compact labeled-row owner, with Field label/help content and metadata. Both
  radio groups use DRadioGroup.controlled and DRadioGroupItem; choice surfaces
  remain DFieldLabel.choice, with shared borrowed item/label focus nodes so label
  clicks support subsequent arrow navigation. Primary/outline example actions
  use the completed Button variants.
- The responsive custom-error example deliberately retains its single native
  FormField/TextField. DInput owns its error display and exposes no error builder;
  retaining that example demonstrates custom DFieldError without inventing a
  second state owner or modifying the completed Input API. Multiline, Switch,
  selection and Slider placeholders remain explicit. No unmerged Switch or
  Textarea source is imported or redesigned.
- Voice's four ordinary editors retain main's DInput values, submission behavior
  and flags, and now compose surrounding DFieldLabel/DFieldControl/help using
  dialog-owned focus nodes. Name activation, required semantics, typing-based
  Save guards, cancellation and latest-controller save are checked. Multiline
  description and switches retain their current owners. Preferences retains its
  existing Field grouping/help and all pinned-main control changes; its 22 tests
  cover section behavior, permissions, async state and persistence.
- Integration semantics tests inspect the combined SemanticsData at the Field
  merge boundary. DInput's deliberate inner semantics container remains intact;
  its editing actions/value combine with the outer Field label/help without
  removing main's page-boundary fixes. No generic Field part was removed.
- The generated runnable snippets were refreshed because their actual controls
  changed. Frozen source/export capture was not repeated.

The Mac remains locked and the coordinator separately reported an admin-policy
failure on first browser navigation. Neither blocker was retried or bypassed;
no CUA, browser or native launch was attempted. Review remains `awaiting_slot`.
The fresh exact-source fixture and restricted-free ad-hoc entitlement read-back
are recorded in field-build.json after the integration source commit.

## Captured reference

- Frozen documentation and all inline examples: https://ui.shadcn.com/docs/components/base/field.md
  SHA256 `1afe174f74b982ec86fad520dab464a16bfe289c2d54fde88241ce3a791112ee`.
- Documentation page: https://ui.shadcn.com/docs/components/base/field
- Official base-nova registry: https://ui.shadcn.com/r/styles/base-nova/field.json
  SHA256 `586110f5563cbb5dc0929207ee34361f1349cf2f816465799c60b98821e4cedc`.
- Captured files, including extracted `field.tsx`, and hashes are in
  `reference/field/`. These are primary-source reads through curl, not a rendered
  browser comparison. The registry source and frozen Markdown cover every
  reference example; no React runtime or external dependency was added.

## CSS to Flutter mapping

Measurements below come from registry CSS at a 16px root rem. They are source
measurements, not claims of rendered pixel parity.

| Reference | Flutter logical geometry |
| --- | --- |
| FieldSet `gap-4`, direct choice group `gap-3` | 16px / 12px |
| FieldLegend `mb-1.5`, medium, base/sm | 6px following margin; 500 weight; legend 16/24px, label 14/20px |
| FieldGroup `gap-5`, nested group `gap-4`, choice `gap-3` | 20 / 16 / 12px; optional spacing for app composition |
| Field `gap-2`, vertical/horizontal/responsive | 8px; single Flex changes direction without replacing child elements |
| `@md/field-group` | 448px nearest group width; outside a group uses own width |
| FieldContent `gap-0.5` | 2px, flexes beside compact controls |
| FieldLabel `text-sm font-medium leading-snug` | 14/19.25px, weight 500; composes merged DLabel |
| FieldTitle `text-sm font-medium` | 14/20px, weight 500; no label action |
| FieldDescription `text-sm leading-normal` | 14/21px, weight 400, muted foreground; directional start alignment |
| Description after default legend `-mt-1.5`, otherwise second-last `-mt-1` | -6px / -4px through sibling gap arithmetic; adjacent legend selector wins |
| FieldSeparator `-my-2 h-5`, content `px-2` | surrounding gaps reduced 8px; 20px minimum height, 8px text masking padding, 1px DSeparator |
| FieldError `text-sm`, list `ml-4 gap-1` | 14/20px; 16px directional bullet allocation and 4px list gap |
| Choice card `rounded-lg border`, Field `p-2.5` | host radius ×1, 1px border + 10px padding (11px content inset) |
| Checked light `border-primary/30 bg-primary/5` | live primary existing alpha ×0.30 / ×0.05 |
| Checked dark `border-primary/20 bg-primary/10` | live primary existing alpha ×0.20 / ×0.10 |
| Enabled hover `bg-muted/50` | live muted alpha ×0.50 |
| Focus-visible `border-ring ring-3 ring-ring/50` | ring-color border; outside-only 3px DRRect paint with live alpha ×0.50 |
| Disabled label `opacity-50` | 50% opacity across the complete choice surface, including border/background/content; pointer/focus guards; underlying controls also receive disabled state |

No artwork belongs to Field apart from ordinary list bullets and the Separator.
Control artwork remains owned by the pending Checkbox/Radio/Switch/etc. tasks.
Typography derives host font family from DText; explicit metrics use unscaled
DiscourseTypography sizes and native inherited text scaling. No fixed swatches
or cached palette are in the component.

Native adaptations are specific: Flutter wraps text normally instead of CSS
text balancing. Directional start alignment supports RTL instead of the source's
literal text-left. Separator text can grow beyond 20px at accessibility sizes.
Negative margins reduce gaps but never create negative Flutter constraints;
FieldContent keeps its 2px readable rhythm. For rich help, callers compose native
links with their own text decoration and independent actions; Field does not
capture those actions. Current native indicators retain their native hit areas
until control reconciliation. DFieldControl.alignIndicatorToContent supplies the
source's checkbox/radio 1px top alignment; compact exact example heights must
still be compared after those owners merge. No stock
Material appearance is claimed as a completed reference-control port.

## Public ownership and accessible usage

All ten reference widgets plus DFieldControl have one owner in
`lib/src/ui/components/d_field.dart` and are exported by `discourse_ui.dart`.
DField accepts children, orientation, invalid and enabled state. It is not a
FormField and never stores value, validation or controller state.

DFieldControl wraps **one** editable/toggle/adjustable control. Supply its label,
description and current errors. MergeSemantics adds this metadata to the native
control without losing setText, selection, toggle or adjustment actions. Errors
also set SemanticsValidationResult.invalid and become part of the control hint.
DFieldError is a separate live region and deduplicates nonempty messages in
first-seen order. Custom content takes precedence. Empty errors do not add gaps.

DFieldLabel gets a borrowed focusNode for editors or the same activation callback
as the choice control. It adds no tab stop or duplicate semantic activation.
Set excludeSemantics on the visual label when DFieldControl names the control.
Help text can also be read independently, analogous to aria-describedby HTML
paragraphs. DFieldSet names its semantic group from a direct Text legend; callers
supply semanticLabel for other rich legends. The legend remains a readable
heading. Disabled groups block pointer/focus access; keep child enabled flags
in sync for control-specific appearance. Borrowed nodes are never disposed.

DFieldLabel.choice supplies the outline/selected/hover/focus surface. Descendant
controls own native keyboard/radio-group behavior and selected semantics. Its
callback handles the card text and empty area; a child control's gesture wins,
so a click does not toggle twice. Keep unrelated links outside a choice card.
The ring follows descendant keyboard focus, not pointer focus. There is no
animation, so reduced-motion has no special transition to suppress.

## Examples and reconciliation

Nine self-contained examples implement Payment Method/Billing/Comments,
Input/Password/Textarea/Select, Price Range, Address Information, Desktop items
and sync, Subscription/Choice cards, grouped notification settings/Switch,
responsive Form validation and Arabic RTL Payment. Each mounts the actual Field
widgets. Full runnable code is generated from the same example classes by
`dart run tool/generate_field_example_sources.dart`.

The frozen references' Input, Textarea, Checkbox, Radio Group, Switch, Slider and
Button branches are unmerged here. Examples explicitly use current native
controls and baseline Button; no other worktree is imported. Select is a native
DropdownButtonFormField placeholder. Coordinator must adopt the merged public
controls and re-run compositions; Label's older FieldDemo handoff, Input's Field
examples and Textarea's Field example should converge on this owner. Radio and
Checkbox choice-card adapters should reuse this surface during integration,
without losing their existing controlled state, Form or keyboard owners.

## Production audit and bounded adoption

- Core Preferences: `_PreferenceCard` replaces its layout Column with DFieldGroup.
  Its section adapters preserve their existing 8/12/20px explicit gaps via
  spacing: 0. Profile's device-timezone help uses DFieldDescription. Combobox
  selection, restore-on-invalid-query behavior, save permissions, callbacks,
  keys, loading/error announcements and persistence are unchanged.
- Voice: actual room editor replaces its zero-gap Column with DFieldGroup (20px).
  The production dialog is now named VoiceRoomEditorDialog, allowing the same
  dialog to return local drafts in the native fixture. showVoiceRoomEditor still
  saves through the latest controller after dismissal. All editing controllers,
  autofocus, required-name guard, draft conversion, permission-driven LiveKit
  option, switches and selection callbacks retain their original owners.
- Core add-instance, composer, topic taxonomy, bookmark, flag, search, group and
  user editors retain inner controls: Input/Textarea own ordinary editors;
  Combobox/Select and domain composer owners handle suggestions/tokens. Field
  should be adopted around them during those owners' serialized reconciliation.
- Bundled Chat (channel editing, preferences, thread settings, member/message
  search), Poll composer (dynamic option/numeric groups), Local Dates (date/time,
  recurrence and countdown), Events (schema-driven custom fields/date editors),
  Assign (assignee search), GIF search and remaining Voice settings/diagnostics
  retain their domain layout/controls. Their active Input/Textarea/Switch/Radio/
  Native Select work overlaps these exact files; broad rewrites are deferred to
  coordinator reconciliation, not treated as permanent fidelity exceptions.
- Reactions, Lazy Videos, Discourse AI, GitHub and Prometheus Alert Receiver have
  no ordinary form-control composition to adopt in this audit. GitHub labels are
  domain badges. packages/discourse_voice is a native bridge and profiles/full
  shares this UI; neither has an independent Field renderer.
- Alert owns inline error/status notices and Empty page-level states. None were
  replaced. FieldError is only validation attached to a particular field.

## Review fixture

`tool/field_review_main.dart` mounts the real PreferencesPage with in-memory
FakeDiscourseApi/stores, and the real VoiceRoomEditorDialog returning a local
draft. It also opens the actual styleguide and mounts Choice/Responsive examples.
Preferences are explicitly in-memory before creating ShellController. No account
credentials, real network transport or voice session are required. The fixture
provides light/dark, RTL and 100/200% controls. It has not been launched while the
Mac is locked; no device or VoiceOver outcome is inferred from widget tests.

## Original branch verification (before pinned integration)

Source commit: `5aa4e377b7399a22dca17263ec62dae20c290090`.

- Root `flutter analyze --no-pub`: clean, final log `/tmp/field-final-analysis.log`.
- Full profile `flutter analyze --no-pub`: clean, `/tmp/field-full-final-analysis.log`.
- Final component/styleguide/Preferences/Voice run: **103 passed**, random seed
  `1870857252`; `/tmp/field-final-tests.log`. This includes 18 Field/example tests.
- Earlier downstream run including Label, Separator and plugin boundaries:
  **132 passed**, seed `734624525`; `/tmp/field-downstream-tests.log`.
- The focused ring pixel check verifies interior pixels are unchanged by focus
  and translucent selected colors retain multiplicative alpha through a live
  palette change. This is a Flutter renderer regression, not reference parity.
- All 11 touched Dart files are formatted; Flutter 3.47.2 and all lockfiles/pins
  remain unchanged. Temporary build dependency resolution used enforced locks.

Exact temporary build identity, source equality, original/copied kernel SHA256
and deep strict signature evidence are recorded in [field-build.json](field-build.json).
The fixture was never launched. Native/reference review remains **awaiting_slot**.

## Integration fixture readiness

Source `e298291e7c85ce47d24049004504c84208d3d07f`; merge of pinned main `6c31531c`.
Root/full analysis and touched formatting pass. The 21 Field/example tests
(seed `2279137221`), 22 Preferences tests and two affected Voice editor tests
pass. Exact commands and logs are in the Field progress row.

Current artifact: `/var/folders/2m/k_kwhr_j70q64prh4z3r44jc0000gn/T/field-integration-ready-e298-vo08i7cv/Field Integration E298.app`.
Bundle `org.discourse.field.e298`; scheme `discourse-field-e298`.
2,869 tracked source entries match the source Git blobs; four temporary runner
files supply the unique identity and ad-hoc debug signing. All pins unchanged.
Original/copied kernel SHA256 `82cce279152dbbe67c9cbef442a44e91801c42676bd71e1108d19d8d5d62fd09`.
Deep strict signature verification passes. Explicit entitlement read-back equals
the seven-key whitelist in field-build.json; no restricted APS/developer/team/
application identifiers or embedded profile remain. Production signing is unchanged.

This artifact supersedes the original fixture record. Status stays
`in_progress / awaiting_slot`; no browser or native access was attempted.
