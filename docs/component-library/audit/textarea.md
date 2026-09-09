# Textarea audit

Audited 2026-09-09 on `claude/audit-textarea` against the live reference.
Implementation: `lib/src/ui/components/d_textarea.dart`. Examples:
`lib/src/styleguide/examples/textarea_examples.dart`. Tests:
`test/d_textarea_test.dart`, `test/d_textarea_visual_test.dart`,
`test/styleguide/textarea_examples_test.dart`.

## Reference

| Source | SHA256 of the fetched bytes |
| --- | --- |
| [Docs page](https://ui.shadcn.com/docs/components/base/textarea.md) | `7f2112811eec73ffe6ddc4f250ab4daad7a9894bd274817dda6e26dec0a03759` (identical to the frozen `reference/textarea/docs.md`) |
| [base-nova registry](https://ui.shadcn.com/r/styles/base-nova/textarea.json) | `8f01f6bc4ee556263bae7644e8b527022fa77ff203f33a258bb47142ef7d9c81` (identical to the frozen `reference/textarea/textarea.json`) |
| [base-nova Input Group registry](https://ui.shadcn.com/r/styles/base-nova/input-group.json) (grouped textarea classes) | `acf9c5497a6c844dee87fbd4afefb6cd8be9ce50d050d14d58a340d955e517a1` |
| [MDN `field-sizing`](https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/Properties/field-sizing) (rows semantics) | `582e95cde420a2b4c02130c70eef08a140e25f76c78489edb16923e15d3cb78e` |

No upstream drift since the 2026-09-08 freeze. Registry `textarea.tsx` is a
plain `<textarea data-slot="textarea">` with `flex field-sizing-content
min-h-16 w-full rounded-lg border border-input bg-transparent px-2.5 py-2
text-base transition-colors outline-none placeholder:text-muted-foreground
focus-visible:border-ring focus-visible:ring-3 focus-visible:ring-ring/50
disabled:cursor-not-allowed disabled:bg-input/50 disabled:opacity-50
aria-invalid:border-destructive aria-invalid:ring-3
aria-invalid:ring-destructive/20 md:text-sm dark:bg-input/30
dark:disabled:bg-input/80 dark:aria-invalid:border-destructive/50
dark:aria-invalid:ring-destructive/40`. There is no shadow class. The docs
page documents the demo, Usage, Field, Disabled, Invalid, Button and RTL.

## Comparison

| Part | Reference | Flutter | Status |
| --- | --- | --- | --- |
| Element | `<textarea>`, no runtime dependency | `DTextarea extends FormField<String>` over a native `TextField`; exported by `discourse_ui.dart` | match |
| Minimum height and growth | `min-h-16` (64px) `field-sizing-content`: grows with content from the minimum; `rows`/`cols` have no effect (MDN) | 64px minimum, `maxLines: null` grows with content; five 20px lines measure 118px; `minLines`/`maxLines` are native extensions that reserve and bound lines | match; the extensions are documented as such |
| Width | `w-full` | `Column(crossAxisAlignment: stretch)` fills the parent | match |
| Padding, border, radius | `px-2.5 py-2` (10/8px), 1px `border-input`, `rounded-lg` (×1.0 host radius) | 10/8px plus 1px border (text inset 11×9), `DTokens.colors.outlineVariant`, `BorderRadius.circular(t.radius)` | match |
| Shadow | none | none | match |
| Fill | `bg-transparent`; dark `bg-input/30` | transparent; dark `outlineVariant` alpha × .3 | match (pixel-checked: 34 ± 1 over #181818) |
| Disabled | `cursor-not-allowed bg-input/50 opacity-50`; dark `bg-input/80`; label in `Field data-disabled` at 50% | forbidden cursor, alpha × .5 / .8 fill, one 0.5 `Opacity` over the box, `IgnorePointer`, focus dropped; `labelText` DLabel dims | match |
| Placeholder | `text-muted-foreground`, same metrics | `hintStyle` = text style with `mutedForeground` | match |
| Typography | `text-base md:text-sm` (16/24 below 768px, 14/20 above), weight 400 | 16/24 on iOS/Android, 14/20 elsewhere; host font family; inherited text scaler | intentional: the breakpoint stands in for phones, where iOS zooms sub-16px fields; platform is the native equivalent and matches Input |
| Focus | `focus-visible:border-ring ring-3 ring-ring/50`; text fields match `:focus-visible` on pointer focus too | border `focusRing`, 3px exterior annulus at `focusRing` alpha × .5 on any focus | match |
| Invalid | `border-destructive ring-3 ring-destructive/20`; dark `border-destructive/50 ring-destructive/40`; `Field data-invalid` colors the label, description stays muted | destructive border (dark alpha × .5), always-visible ring alpha × .2 / .4, invalid semantics; `labelText` turns destructive, `helperText` stays muted | match |
| Hover | no rule | none | match |
| Motion | `transition-colors`: border and background over 150ms `cubic-bezier(0.4, 0, 0.2, 1)`; the ring is a box shadow outside that list and appears at once; opacity is not transitioned | previously ring and border faded together on a linear curve; now `AnimatedContainer(curve: Curves.fastOutSlowIn)` eases border and fill while a foreground painter draws the ring immediately; opacity snaps; zero duration under reduced motion | fixed in c1f7da24 |
| Pointer over the box | the whole box is editable: text cursor over the padding, a press anywhere focuses | previously arrow cursor and no reaction on the 10×8px inset; now the surface shows `SystemMouseCursors.text` and a padding press requests focus, while the TextField's recognizers keep presses inside it | fixed in c1f7da24 |
| Resize grip | browser default `resize: both` handle | none; content growth and `maxLines` bound height | intentional: a drag-to-resize handle would need a second height owner competing with content growth and parent constraints, and no native platform textarea has one |
| Read-only | `readOnly` attribute, no visual rule, still focusable | `readOnly` forwarded; selection, copy and focus ring remain | match |
| Selection colors | browser default `::selection` | theme `TextSelectionThemeData` | match (app-owned in both) |
| Keyboard | Enter inserts a newline, Tab moves focus | `TextInputType.multiline` + `TextInputAction.newline`; Tab traverses | match |
| Semantics | `textbox` multiline, `aria-invalid`, `aria-required`, label by `htmlFor` | `Semantics(container: true, label, isRequired, validationResult)` bounded to the editor; error text is its own live region | match |
| Text scaling | rem-based box | 64px and insets fixed; text scales and the box grows with it | intentional: the native scaler owns text only, as for Input |
| RTL | `dir` on Field, label, textarea, description | inherited `Directionality`; `textDirection` override | match |
| Inside Input Group | `InputGroupTextarea`: `py-2`, no border/ring/fill of its own, group min-height auto | in a `DInputGroupControlScope` the field renders `Padding(10, 8)` around the editor only | match |
| Demo / Usage | `<Textarea placeholder="Type your message here." />` | Default example | match |
| Field | `Field > FieldLabel + FieldDescription + Textarea`: 4px label→description, 8px description→control | previously a raw Column with `Text` and a `Semantics` wrapper; now `DField > DFieldLabel(focusNode) + DFieldDescription + DFieldControl(DTextarea)` with the same gaps and one merged name/description | fixed in 1a7c4801 |
| Disabled | `Field data-disabled > FieldLabel + Textarea disabled` | `DTextarea(labelText: 'Message', enabled: false)` | match |
| Invalid | `Field data-invalid > FieldLabel + Textarea aria-invalid + FieldDescription` | `DTextarea(labelText, invalid: true, helperText)` | match |
| Button | `div.grid.w-full.gap-2 > Textarea + Button "Send message"` | previously merged into a Form demonstration with an extra Reset button; now a stretched `Column(spacing: 8)` with a full-width `DButton` that sends locally, and the Form demonstration is its own example | fixed in 1a7c4801 |
| RTL | `Field className="w-full max-w-xs" dir` with label, `rows={4}` textarea, description | previously `minLines: 4` reserved 98px where the reference `rows` is inert under `field-sizing: content`; now the 64px minimum inside a 320px `ConstrainedBox` | fixed in 1a7c4801 |

## Implementation review

No lifecycle, race, Form or cached-theme defects were found: borrowed
controllers, focus nodes, scroll and undo controllers are never disposed and
controller/focus switches re-attach listeners; equal `value` strings leave
selection and composing untouched while `_syncing` keeps programmatic writes
out of `didChange`; `reset` restores the mount snapshot; tokens are read in
`build`; the editable role is a bounded `Semantics(container: true)`; every
public property reaches the `TextField`. The 14 application call sites
(invites, groups, post flag/notice/fast edit, Assign, Chat, Events, Voice) and
`DInputGroupTextarea` pass only public parameters and are unchanged.

## Issues

1. Fixed in c1f7da24: the focus/invalid ring faded in with the border on a
   linear curve; the reference `transition-colors` eases only border and fill,
   with `cubic-bezier(0.4, 0, 0.2, 1)`, and shows the ring at once.
2. Fixed in c1f7da24: the box's 10×8px inset showed an arrow cursor and did not
   focus the editor when pressed.
3. Fixed in 1a7c4801: the Field example bypassed the merged Field owners.
4. Fixed in 1a7c4801: the Button example was not the reference composition.
5. Fixed in 1a7c4801: the RTL example reserved four lines for an inert `rows`.
6. Intentional: platform-based 16/24 vs 14/20 text (reference `md:` breakpoint);
   no resize grip; fixed 64px box under text scaling. Rationale in the table.
7. Open, shared with Input: `FormFieldState.reset` calls `onReset` after
   setting the state value to the latest `widget.initialValue`, one call
   before `DTextarea` restores the mount snapshot. Only a caller that reads
   `value` inside `onReset` after changing a controlled `value` observes it,
   and the Input owner chose the same sequence; changing it belongs to both.

## Verification

Run in the audit worktree on Flutter 3.47.2 after `flutter pub get
--enforce-lockfile` (no lockfile change).

- `dart format lib/src/ui/components/d_textarea.dart lib/src/styleguide/examples/textarea_examples.dart test/d_textarea_test.dart test/d_textarea_visual_test.dart test/styleguide/textarea_examples_test.dart`: clean.
- `flutter analyze --no-pub` (root): no issues. `(cd profiles/full && flutter analyze --no-pub)`: no issues.
- `flutter test --no-pub --test-randomize-ordering-seed=random test/d_textarea_test.dart test/d_textarea_visual_test.dart test/styleguide/textarea_examples_test.dart`: 22 passed, seed 844076832.
- `flutter test --no-pub --test-randomize-ordering-seed=random test/styleguide/styleguide_page_test.dart test/d_input_group_test.dart test/styleguide/field_examples_test.dart test/styleguide/label_examples_test.dart test/ui/d_field_test.dart test/ui/d_label_test.dart test/assignment_sheet_test.dart test/invite_list_test.dart test/post_flag_editor_test.dart test/voice_room_view_test.dart`: 171 passed, seed 3541551224.
- With main's `d_textarea.dart` restored over the new tests, the three new
  tests fail (arrow cursor on the padding; ring absent on the first frame;
  border already at the focus color) and the 19 others pass.
- `git diff --check`: clean.

No shared foundation file changed. No native app, simulator or browser was
run; this is a source-level audit backed by widget tests.
