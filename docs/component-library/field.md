# Field implementation and review handoff

Branch `codex/ui-field`, base `402fe578`. Field remains **in_progress**;
styleguide status is baseline until reference/native review and dependent-control
reconciliation. No desktop/browser slot was used. See its progress row for checks
and build evidence.

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
| Disabled label `opacity-50` | 50% label/content opacity; pointer/focus guards; underlying controls also receive disabled state |

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
