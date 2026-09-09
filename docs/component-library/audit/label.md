# Label audit

Audited on **2026-09-09** against the live reference, on branch
`claude/audit-label`. Implementation: `lib/src/ui/components/d_label.dart`;
examples: `lib/src/styleguide/examples/label_examples.dart`; tests:
`test/ui/d_label_test.dart`, `test/styleguide/label_examples_test.dart`.

## Reference

| Source | SHA256 of the fetched bytes |
| --- | --- |
| [Docs Markdown](https://ui.shadcn.com/docs/components/base/label.md) | `7263b641bac78acd5ec6cfbffefeddda484eaedb1d32b8a73a675b53da0644c2` (unchanged since the 2026-09-08 freeze) |
| [base-nova registry](https://ui.shadcn.com/r/styles/base-nova/label.json) | `89b01e14fd39dceece9fa421e71e78ea83286bd43a2ca1c2f55d2e8d3958fff2` (unchanged) |
| [Theming](https://ui.shadcn.com/docs/theming.md) | `403a71fea629dd9d5eebdf3656baab6b8550972adfb4fc5ed0847d13b3dc73f0` |

Registry `label.tsx` is a plain `<label data-slot="label">` with
`flex items-center gap-2 text-sm leading-none font-medium select-none
group-data-[disabled=true]:pointer-events-none group-data-[disabled=true]:opacity-50
peer-disabled:cursor-not-allowed peer-disabled:opacity-50`. It is `flex`, not
`inline-flex`. The docs page documents LabelDemo (Checkbox + Label), the Usage
snippet (`htmlFor="email"`), Label in Field (FieldLabel + Input, plus the full
FieldDemo), RTL (Arabic/Hebrew) and the Base UI API link (HTTP 404, as recorded
at implementation time).

## Comparison

| Reference | Flutter | Status |
| --- | --- | --- |
| `<label>` element, `data-slot="label"` | `DLabel`, exported by `discourse_ui.dart`; no runtime dependency | match |
| `text-sm leading-none font-medium`, inherited `text-foreground` | 14 logical px, line height 1, weight 500, tracking 0 over `DText` small; live `DTokens.foreground`; host font family and text scaler retained | match |
| `select-none` | `SelectionContainer.disabled`; a `SelectionArea` ancestor registers prose but not labels | match |
| `flex items-center gap-2` (container geometry; no padding, border, radius) | Single `child`; icon/text content composes `Row(crossAxisAlignment: center, spacing: DSpacing.sm)` with a flexible text child (rich example). No outer spacing. | match by composition: a generic `children` API cannot know which child shrinks to wrap, so the gap is stated on the component and shown in the example |
| `peer-disabled:opacity-50 cursor-not-allowed` | Slot owners derive it from the control (`DCheckbox`, `DSwitchTile`, `DRadioGroupItem`, `DInput`, `DTextarea`, `DNativeSelect`, `DFieldLabel`): opacity 0.5 applied once, forbidden cursor. Standalone `enabled: false`: opacity 0.5, forbidden cursor, disabled semantics, `IgnorePointer`, `ExcludeFocus` | match |
| `group-data-[disabled=true]:pointer-events-none opacity-50` | `DFieldLabel` reads the field scope and disables its `DLabel`; `DFieldSet(enabled: false)` adds `IgnorePointer`/`ExcludeFocus` and controls pass their own enabled flag | match (a bare `DLabel` inside a disabled field set follows its control, the documented `DFieldSet` contract) |
| LabelDemo: `div.flex.gap-2` > Checkbox `id` + Label `htmlFor`; clicking the label toggles, one accessible name | `DCheckbox(title: DLabel)`: 16 px control, 8 px gap, centered row; label tap and Space toggle; `MergeSemantics` yields one node with checked/enabled state and one tab stop | match |
| Usage: `<Label htmlFor="email">` focuses the input | `DInput.labelText` / `DTextarea.labelText` / `DNativeSelect.label` / `DFieldLabel(focusNode:)` request focus; the editor owns the accessible name | match |
| Label in Field: `Field > FieldLabel htmlFor > Input id` | Form example: `DField > DFieldLabel(focusNode) + DFieldDescription + DFieldControl(DInput(focusNode))`, required semantics, error, save and reset | match |
| FieldDemo (Payment Method, Select month/year, CVV, Billing checkbox with `font-normal`, Textarea, Submit/Cancel) | Reproduced by the Field examples (`field_examples.dart`, "Payment Method"); `font-normal` maps to `DLabel(style: TextStyle(fontWeight: w400))` as in the Checkbox Group example | match, owned by Field |
| RTL: `dir` on container, checkbox and label; ar/he strings | `DDirection(rtl)` with Arabic and Hebrew `DCheckbox(title: DLabel)`; leading control on the right, `TextAlign.start`, wrapping | match (both languages shown at once instead of a language selector) |
| Standalone `htmlFor` id association | None: Flutter has no element id registry and the accepted criteria forbid adding one or a second focus system; the slot owner associates | intentional |
| Enabled cursor `default` | `MouseCursor.defer` | match |
| Semantics of a disabled label | `Semantics(enabled: false)` bounded to the label subtree, merged into the control's node inside a slot | match |

## Issues

1. **Fixed.** A `DLabel` passed into a slot that wraps it in its own `DLabel`
   (`DRadioGroupItem.label`, `DFieldLabel.child`) reset the composer's line
   height to 1 and replaced its invalid color with the foreground, and a
   disabled label nested in a disabled label dimmed twice (0.25). `DLabel` now
   publishes a private scope; a nested label inherits the enclosing metrics,
   merges only its own `style`, and dims only when the enclosing label has not.
   Pinned by the nested, radio-slot and dim-once tests in `d_label_test.dart`.
2. **Fixed.** The doc comment named Material `SwitchListTile`/`RadioListTile`
   and described Input and Field as pending; it now lists the merged slot
   owners, the `htmlFor` mapping and the nesting rule.
3. **Fixed.** The rich example expressed `gap-2` as a `SizedBox`; it now uses
   `Row.spacing` in both the snippet and the preview. The association example
   said the label "receives the same enabled state" while its snippet passes
   none; the description now states that the control derives it.
4. **Fixed.** `label-visual-mapping.md` still described the tile and
   `TextFormField` composition as temporary; it now points here.
5. **Intentional.** `DCheckbox` and `DSwitchTile` unwrap a title `DLabel` and
   ignore its `enabled` flag: they derive the treatment from the control, as
   the reference `peer-disabled` selector does, and `d_switch_test.dart` pins
   "opacity applied once". The flag is documented as standalone-only.
6. **Intentional.** No standalone id association (see the table).

No lifecycle, cached-theme or unbounded-semantics defects were found: `DLabel`
is stateless, owns no nodes, reads tokens in `build`, and only emits a
semantics flag when disabled. Callers in `lib/` and `profiles/` pass `DLabel`
into slot titles or use it standalone; none nest one label inside another
outside the radio examples, so their rendering is unchanged.

## Verification

Run in the audit worktree on Flutter 3.47.2 with `flutter pub get
--enforce-lockfile` (no lockfile change).

- `dart format --output=none --set-exit-if-changed lib/src/ui/components/d_label.dart lib/src/styleguide/examples/label_examples.dart test/ui/d_label_test.dart`: clean.
- `flutter analyze --no-pub`: no issues.
- `git diff --check`: clean.
- `flutter test --no-pub --test-randomize-ordering-seed=random test/ui/d_checkbox_test.dart test/ui/d_field_test.dart test/ui/d_native_select_test.dart test/d_radio_group_test.dart test/d_switch_test.dart test/d_input_test.dart test/d_textarea_test.dart test/d_progress_test.dart`: 116 passed, seed 1481752454.
- `flutter test --no-pub --test-randomize-ordering-seed=random test/ui/d_label_test.dart test/styleguide/label_examples_test.dart test/styleguide/styleguide_page_test.dart test/styleguide/checkbox_examples_test.dart test/styleguide/field_examples_test.dart test/styleguide/input_examples_test.dart test/styleguide/textarea_examples_test.dart test/styleguide/progress_examples_test.dart test/styleguide/native_select_examples_test.dart test/radio_group_review_fixture_test.dart test/switch_review_fixture_test.dart test/post_flag_editor_test.dart test/voice_diagnostics_view_test.dart test/preferences_page_test.dart test/plugins/poll/poll_composer_sheet_test.dart`: 123 passed, seed 3034494194.

The three new label tests failed before the fix (line height 1.0, foreground
color, two 0.5 opacities) and pass after it. No shared foundation file
changed. No native app, simulator or browser was run; this is a source-level
audit backed by widget tests.
