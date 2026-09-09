# Input implementation and reference evidence

Task: `01a083ad-3168-7c01-b35a-7271f9fe6326`; branch: `codex/ui-input`.
Base: local main `2e894b5e`. Label is merged. File selection composes Button;
the coordinator must merge Button before reviewing/integrating Input.

## Source

Read the official [Input page](https://ui.shadcn.com/docs/components/base/input),
its [Markdown](https://ui.shadcn.com/docs/components/base/input.md), and the
[base-nova registry](https://ui.shadcn.com/r/styles/base-nova/input.json) on
2026-09-09. The local copies are `reference/input.md` and `reference/input.json`.
The Markdown SHA256 exactly matches the frozen catalogue:
`1ea19da544283cee29e704fc9c7e930b55fef45018710427e7243e4be93879f4`.
Registry SHA256:
`bbad1bba130ac9750a61844eeb8f043e8a710846e07689fa85398b80a46c2741`.
Upstream license is preserved in `reference/LICENSE.shadcn.md`.

| Official CSS / behavior | Flutter mapping |
| --- | --- |
| `h-8 w-full min-w-0` | 32px minimum visual height, parent width, Expanded editor with horizontal native scrolling |
| `px-2.5 py-1`, one-pixel border | 10px horizontal padding inside the border; centered 20px desktop line with 5px vertical inner space at the 32px border-box height |
| `rounded-lg` | host `DTokens.radius`, the library's mapped lg radius |
| `text-base md:text-sm` | 14/20px on desktop, 16/24px on touch platforms; host font, weight 400, zero tracking |
| `border-input bg-transparent` | `DTokens.colors.outlineVariant`, transparent light background |
| `dark:bg-input/30` | input token alpha multiplied by 0.3 |
| `placeholder:text-muted-foreground` | live mutedForeground, same metrics as entered text |
| `focus-visible:border-ring ring-3 ring-ring/50` | token focus border and 3px outward 50% ring; text fields show focus for pointer and keyboard entry |
| disabled pointer blocking, `bg-input/50 opacity-50` | disabled native editing plus pointer exclusion, input-token alpha multiplied by 0.5, whole input opacity 50% |
| dark disabled `bg-input/80` | input-token alpha multiplied by 0.8 before outer disabled opacity |
| invalid destructive border, `ring-3 ring-destructive/20` | destructive border and persistent 3px/20% ring, error text and invalid semantics |
| dark invalid border `/50`, ring `/40` | corresponding 50% border and 40% ring |
| `transition-colors` | 150ms color decoration transition, zero when reduced motion is requested |
| file `inline-flex h-6`, transparent borderless 14px medium button | DFileInput composes Button, FormField list-of-display-names and the same input surface; native file picker supplied by caller |

Large text increases intrinsic height; clipping text to 32px would make editing
unusable. Touch fields have a transparent 48px minimum hit region around their
compact visual surface. Native platform font metrics and the app's palette,
font family and radius intentionally replace the website's theme variables.
There is no Material outline or floating label renderer.

## Editing contract

DInput extends FormField<String> and delegates editing, selection, IME,
autofill, keyboard commands, context menus and undo to TextField/EditableText.
There is one optional borrowed controller and one optional borrowed focus node;
otherwise DInput owns and disposes them. Borrowed resources are never disposed.
Controller-to-local handoff copies the complete TextEditingValue. Selection and
composition changes never write back into the controller or notify Form.
Programmatic text changes update the Form value but not the user onChanged
callback; user text changes notify Form once.

`initialValue`, `value` and `controller` are mutually exclusive. Equal controlled
strings leave selection/composition untouched. A different controlled string
replaces text, collapses selection at its end and clears composition. Local
initialValue changes do not overwrite an edit. Form.reset restores the value
captured at mount in all modes, matching the pinned Flutter TextFormField;
Form state and visible controller text are explicitly synchronized after reset.
Reset calls onChanged once. Validators, save, reset and autovalidation remain
Flutter Form contracts. `isRequired` supplies native semantics; callers provide
their actual validation rules.

Read-only remains focusable/selectable. Disabled input cannot edit or retain
focus. A label activates the same focus node without an additional tab stop.
Its semantic name and invalid/required state attach directly to the editable
node even with a prefix or an interactive suffix. Error text wraps and announces
changes. Prefix/suffix children sit in TextFieldTapRegion so clear/status
controls do not cause an unrelated outside-tap dismissal.

DFileInput's callback owns platform filtering, multiple selection and file
handles. Returning null cancels; an empty list clears. Display names are Form
values; uploading and file bytes are never owned by the UI component. Busy
activation is suppressed; reset invalidates pending completion, disposal is
safe, and picker failure shows a retryable error. No nested text FormField is
used for the file value.

## Frozen sections and ownership

Basic, disabled, invalid, secure/email/phone/URL/search text, required validation,
Form save/reset, inline composition, responsive grid, file and RTL editing are
implemented and demonstrated. HTML button/reset/submit types map to DButton and
Form actions, not fictitious text-input types. `outline`, `secondary`,
`orientation=horizontal` and `align=inline-end` in the catalogue describe adjacent
components, not Input variants.

Field, Field Group, Badge, Input Group and Button Group examples in the frozen
page compose those owners. This task demonstrates static labels/descriptions,
ordinary Row/Column/grid layouts and simple prefix/suffix slots. It does not
export Field layouts, merged group borders, addon positions, OTP cells or
multiline editing. Those catalogue tasks must add their complete compositions
using Input. The country Select in the full reference form remains with Select.

## Application audit and migrations

Inspected the current core and plugin TextField/TextFormField usages as well as
the frozen inventory. Migrated actual single-line fields in:

- `add_instance_sheet.dart`: URL input, debounced lookup status, error, busy
  guard, URL keyboard and Go submission; site discovery/business logic unchanged.
- `invite_editor.dart`: optional email/description, redemption limit and expiry;
  existing formatters, length limits, validators and conditional email behavior.
- `topic_change_owner.dart`, `topic_move_posts.dart`: user/topic searches and
  new-topic title, preserving asynchronous stale-session ownership guards.
- `composer_link.dart`: link URL/anchor, focus, keyboard actions and insertion.
- `post_permanent_delete.dart`, `message_create_button.dart`: confirmation and
  message title validation/submission.
- Chat `chat_channel_editor.dart` and `chat_thread_settings.dart`: names, slug
  and thread title with existing permissions, save callbacks and length limits.
- GIF `gif_picker.dart`: query, formatter, search action, debounce, clear/focus
  and pending indicator. Removed obsolete padding from the indicator slot.
- Poll `poll_composer_sheet.dart`: title, close timestamp, option text and
  numeric range fields; retained native sheet ownership and validation.
- Local Dates `local_date_composer_sheet.dart`: format, timezone, date and time
  editing with existing keyboard actions and stale-picker guards.
- Events `event_composer.dart`: shared single-line attributes and date-picker
  suffix, preserving event serialization and apply/remove guards.
- Voice `voice_room_editor.dart`: room name, maximum participants, chat channel
  ID and idle minutes; media settings and network behavior unchanged.
- `DSidebarInput`: removed its duplicate TextField decoration owner; adapter now
  delegates to DInput. The shared Sidebar documentation shell is preserved.
- Documentation search: DInput now owns editing/visuals; the old private
  Material InputDecoration is removed. Controller, shortcut, clear and mobile
  navigation state remain with the documentation shell.

Adjacent Button imports and Checkbox/Switch controls are otherwise preserved;
the coordinator reconciles shared-file changes during sequential local merges.

### Retained alternatives

- Multiline chat/forum composers, post fast edit, descriptions, custom invite
  message, flags, group messages, diagnostics text and other min/maxLines fields
  remain with Textarea/Input Group and the app's rich editing owners. Their
  highlighting, projected selections and atomic composer components cannot be
  converted into a single-line Input.
- Borderless embedded forum-tab titles and composer-title editing retain their
  inline shell geometry. They are not standalone bordered form fields.
- `topic_filter_input.dart`, `anchored_picker.dart`, `choice_menu.dart` and
  mention/tag/member selection compositions keep their current query renderer
  pending Command/Combobox/Input Group work; their popup focus, token placement
  and selection geometry need verification as a complete compound widget.
- Group management's schema helpers mix single and multiline field ownership
  and inline validation; they remain for Field/Textarea adoption instead of
  adding another shared rendering abstraction in this task.
- Other directory/search compositions (groups/users, diagnostics, invite list,
  emoji, Chat browse/search, Assign and event directory/participants) retain
  their existing filter layouts for the corresponding compound-owner audit.
  DInput's simple search API is now available; these are recorded remaining
  adoption opportunities, not claimed completed migrations.
- Existing non-Input styleguide examples retain their native field fixtures
  until their owning examples' integration pass. The Input page itself uses the
  real DInput/DFileInput, and the documentation search is migrated.

## Verification

Source analysis is clean at root and full profile. The dedicated editing tests
cover controller handoff, IME-preserving rebuilds, controlled replacement,
reset semantics, validation/save, one Form change per edit, secure/formatter
submission, read-only/disabled focus and large RTL text. The example tests mount
all seven real examples at 320px and 200% in Light, Dark, Forest and Plum.

Actual command results, final source/build provenance and native observations
are recorded below when complete. Native inspection has not yet occurred; the
coordinator has reported the Mac locked. No reference parity or review-ready
claim is made by passing tests.

### Prepared native build

Implementation source: `ae4aa4a8b33115981a15b23fa714fb87501fab6e`.
Command: `flutter build macos --debug --no-pub -t tool/input_review_main.dart`.
Build log: `/tmp/input-final-native-build.log`.
Isolated copy: `/private/tmp/DiscourseInputReview-01a083ad.app`.
Bundle ID: `org.discourse.native.input.01a083ad`; display name:
`Input Review 01a083ad`; URL scheme: `discourse-input-review-01a083ad`.
Deep strict ad-hoc signature verification passed. The source-build and isolated
copy kernel SHA256 are both
`f9d9ddb13dba95a076d165d84db1eafcbfd3215232bb161782ad53b17e647089`.
Only the isolated copy's Info.plist and signature were adjusted. The real
running app and the main checkout build directory were not touched. The bundle
has not been launched; desktop authorization and native comparison are pending.

Final focused impact run (19 suites, seed `928374611`): 357 passed and one new
semantics assertion required a frame pump before reading its updated value.
After that test-only correction, all 12 Input tests and the Button adoption
guard passed (13 total) with the same seed. The broad run includes Voice, Chat,
link editing, app validation/stale-session behavior, Sidebar and documentation
navigation. Logs: `/tmp/input-final-focused.log`, `/tmp/input-final-unit.log`.
Root and full-profile final analysis logs:
`/tmp/input-final-analysis.log`, `/tmp/input-final-full-analysis.log`.

### File target and responsive form refinement

The file surface is now a centered background behind the Button and file name.
At desktop scale 100% it remains 32px; at 200% it grows to 48px. Touch permits the
Button's full 48px target without a tight height constraint or clipping. The
file label explicitly keeps 14/20px medium text and zero padding. Once Button
is integrated, select its 24px `DButtonSize.extraSmall` instead of this base's
`small`; do not use its default 12/16px file-label metrics.

Form example fields use stable FormField keys across grid/stack reparenting.
Changing width and palette preserves their controller identity, edit and mount
reset baseline. All 20 Input and example tests pass after these refinements
(seed `928374611`), as do root/full-profile analysis and the native fixture
rebuild. Logs: `/tmp/input-final-refinements.log`,
`/tmp/input-refinements-analysis.log`, `/tmp/input-refinements-full-analysis.log`,
`/tmp/input-refinements-native-build.log`.

Latest native source checkpoint:
`4e1eb3b3fe499868e4ee70f86cb48a987c4040e8`. The isolated bundle at the same path
was refreshed after the refinements. Both source and isolated kernels now have
SHA256 `400b22d515a8be38b71865ddbf53b4c56da175574bbc96ef0d4473b83e959506`.
The unique identity/scheme and deep strict signature are verified again.
This supersedes the earlier unlaunched bundle; it has still not been launched.


## Source/render correction — input role, alpha and exterior rings

Read the coordinator's latest main `visual-fidelity.md` for this bounded
correction. Re-fetched the primary base-nova Input registry; its SHA256 remains
`bbad1bba130ac9750a61844eeb8f043e8a710846e07689fa85398b80a46c2741`.
The public source is unchanged; these corrections fix the Flutter mapping.

- `border-input` and `bg-input` now use `DTokens.colors.outlineVariant`, which
  can differ from `DTokens.border`. Every source opacity modifier multiplies
  the token's existing alpha, including focus and destructive colors. A neutral
  dark input token with alpha .15 becomes .045 for its enabled background.
- A custom interpolating foreground decoration paints the 3px exterior annulus
  with `Canvas.drawDRRect`. It does not paint behind the transparent/translucent
  field interior. The existing 150ms/reduced-motion color transition is retained.
- DFileInput has one 50% opacity owner around the surface and content. Its
  background renderer does not add a second fade. The real DButton keeps a
  null callback and disabled semantics; its existing theme `disabledOpacity`
  override is set to 1 locally because the file field already owns fading.
  Trigger and filename therefore receive the same effective half-opacity.
- Mount-time TextFormField reset semantics are unchanged.

### Flutter export and pixel evidence

`test/d_input_render_test.dart` explicitly loads the repository's JetBrains Mono
font with FontLoader; the exports are not Ahem-font fixtures. Eight exports in
`evidence/input/correction/` show dark default/focused/invalid/disabled, light
invalid, a custom translucent-blue input role distinct from the purple border
role, and enabled/disabled file fields. They are 340×72 physical pixels at 1×,
including 20px margins around the real 300×32 desktop component. The custom
palette deliberately makes input, border, focus and destructive roles distinct.
The font and image hashes are in `manifest.json` in that directory.

The automated pixel checks establish, within 2 RGB levels of alpha compositing:

- neutral dark fill equals white at `.15 × .3` over `#101010` (about `#1b1b1b`);
- that interior color is unchanged in focused and invalid states;
- focus and invalid color is present 2px outside the field and absent 4px out;
- disabled dark fill includes `.15 × .8 × .5`;
- custom input alpha and transparent light interiors remain correct;
- opaque file-trigger and filename glyph cores both become approximately
  RGB 136 over RGB 16 when disabled (tolerance 3), rather than compounding the
  Button's prior additional fade. The trigger also retains disabled semantics
  and cannot invoke the picker.

Inspected the exported focused, custom-invalid and enabled/disabled file images
locally. This is font-loaded Flutter rendering plus analytic source-color
comparison, not a browser comparison or native desktop interaction. No CUA,
browser/app launch, unlock workaround or real-app action was used.

All 363 focused component, example and migrated-app tests pass with seed
`928374611` after the correction. Root/full-profile analysis, formatting and
`git diff --check` pass; the exact-source isolated macOS fixture rebuild passes.
Logs: `/tmp/input-correction-focused.log`,
`/tmp/input-correction-final-analysis.log`,
`/tmp/input-correction-full-analysis.log`, `/tmp/input-correction-native-build.log`.

Button's final merge still owns file-trigger enum/import reconciliation: this
branch uses the actual baseline `DButtonSize.small` with zero padding and the
explicit 14/20 medium label. The completed 24px API must be selected and its
inherited-disabled-style override rechecked after that dependency merges.
No other worktree's Button source or unmerged API was imported. Native inspection
remains `awaiting_slot`; Input stays `in_progress`.

Latest corrected native source: `3800505aacce361f92bc71ff18332f58bf3cb07e`. Refreshed the same
unique isolated bundle and verified its identifier/scheme and deep strict
ad-hoc signature. Source-build and copied kernels both SHA256
`661a1bb69eaf830e8c84de3f2931d1f2df5b760ea3dc4e86980c386cd243939a`. This supersedes previous
unlaunched checkpoints. No launch or CUA/native interaction was performed.

## Official browser comparison, 2026-09-09

Used the exclusively granted browser slot on the official
https://ui.shadcn.com/docs/components/base/input page. Saved computed styles and
crops in `evidence/input/browser/` cover dark default/focus/disabled/invalid/file/
RTL, light default/disabled/invalid/file and a 390px narrow viewport. The reference
uses Geist (Noto Sans Arabic for RTL). Desktop inputs are 32px high with 1px border,
4px vertical and 10px horizontal padding, 10px radius and 14/20px text. The actual
text inset is 11px including the border. Narrow text is 16/24px. File-selector
button is 24px high, weight 500, 14/20px text, no padding/border and 4px right margin.
FieldLabel uses 14/19.25px, FieldDescription 14/21px, both with 8px composition gaps.
Dark input background is white at .15 × .3; disabled changes this to .15 × .8 before
outer .5 opacity. Focus and invalid rings are exterior 3px, matching the corrected
Flutter painter and alpha tests.

Corrected the file-trigger gap from 12px to 4px and supplied the measured Field
label/description leading in DInput's convenience composition. The shared DLabel
component's standalone defaults remain owned by Label. An actual errorText stays
red and live-announced; it is not the reference's muted FieldDescription. The
reference's invalid parent Field also colors its label/entered text, which remains
Field composition ownership rather than an intrinsic Input style.

`test/input_reference_render_test.dart` renders all seven registered builders in
both app palettes and the actual Add Site and Invite editors. Sixteen 600×850
exports in `evidence/input/flutter-reference/` explicitly load repository JetBrains
Mono through FontLoader and apply it to the text theme. They are readable app
palette/geometry evidence, not native screenshots or exact Geist glyph goldens.
Inspected the field states, Add Site, Invite and file images. Geometry assertions
verify label leading (Flutter rounds 19.25 to 19 at 1×), description 21px, 11px text
inset and 4px file gap. Existing 320px/200% RTL examples and native touch target
adaptations remain covered. Flutter's touch field may grow above the browser's
fixed 32px to retain 16/24 text plus padding and its transparent 48px hit target.
Button's final 24px enum and disabled theme reconciliation remain coordinator-owned.

After the interrupted turn, Input tab 1360425200 was absent from browser inventory.
No replacement tab was opened and no other tab was modified. Explicitly RELEASED
the browser slot to the coordinator before final tests/build. The prior tab's
light theme and 390×844 viewport restoration could not be verified because the tab
was gone. Native access remains ungranted; no getApp or native launch occurred.

Final comparison checkpoint `a1020b6745954e54d72183729bc2f86049a949e6`: all 366 focused tests pass with seed
`928374611`; root/full analysis and native build pass. Logs:
`/tmp/input-browser-focused.log`, `/tmp/input-browser-analysis.log`,
`/tmp/input-browser-full-analysis.log`, `/tmp/input-browser-native-build.log`.
Refreshed unique `/private/tmp/DiscourseInputReview-01a083ad.app`; deep strict
ad-hoc signature passes. Source/copy kernels both SHA256
`b034361de32ad1e22d036fc1d4e0334f262b4ce1bc5eeee287751ad748211ba3`. Bundle unlaunched; Input remains
`in_progress` / `awaiting_slot`.
