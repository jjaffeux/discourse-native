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
| `border-input bg-transparent` | token border, transparent light background |
| `dark:bg-input/30` | token border at 30% opacity |
| `placeholder:text-muted-foreground` | live mutedForeground, same metrics as entered text |
| `focus-visible:border-ring ring-3 ring-ring/50` | token focus border and 3px outward 50% ring; text fields show focus for pointer and keyboard entry |
| disabled pointer blocking, `bg-input/50 opacity-50` | disabled native editing plus pointer exclusion, border-token fill at 50%, whole input opacity 50% |
| dark disabled `bg-input/80` | 80% fill before outer disabled opacity |
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
