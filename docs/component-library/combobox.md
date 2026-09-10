# Combobox reference and native mapping

## Source pin

- Frozen documentation: `https://ui.shadcn.com/docs/components/base/combobox.md`
  - retrieved 2026-09-09
  - SHA256 `1999428362ac7386c7770217e5b48e1a44c2b414005f9721ef68b9366e9ef0f2`
  - matches the frozen catalogue exactly
- Official Base Nova registry: `https://ui.shadcn.com/r/styles/base-nova/combobox.json`
  - retrieved 2026-09-09
  - SHA256 `d4b9231b00428269f6fa42bf3e26714f15c69245f35b62d1bbae6d1a4853d314`
  - source path `registry/base-nova/ui/combobox.tsx`
- Base UI API Markdown: `https://base-ui.com/react/components/combobox.md`
  - retrieved 2026-09-09
  - SHA256 `0ef20214794c6e06ddae5f448fa37f598f2e5ff92e0602993ad31eeffa68ca27`

The reference docs define Combobox as a filterable Select restricted to
predefined values. Free-form search boxes remain search controls. The API
separates selected value, input value, open state and highlighted value; supports
flat/grouped/dynamic/externally-filtered items; and documents disabled items,
custom equality and labels, async replacement, multiple selection, chips,
input-inside-popup, clear, status and collision-aware positioning.

## Reference-to-Flutter mapping

| Base Nova reference | Flutter mapping |
| --- | --- |
| `Root` controlled/default value, input, open and highlight | `DCombobox<T>` FormField constructors plus independently controlled `query`, `open`, `highlightedValue` with `highlightControlled`, callbacks and `DComboboxController<T>` |
| flat `items`, grouped items and `Collection` | immutable `DComboboxOption<T>`, `DComboboxOptionGroup<T>`, `DComboboxList<T>` and `DComboboxCollection` |
| internal/custom/external filtering | default case-insensitive substring matching, `DComboboxFilter<T>`, `searchText`, or `filterLocally: false` with safely replaced options |
| 32px input, 14/20 text, 10px start inset | compact input surface, `DiscourseTypography.sm`, 20px leading and logical padding |
| input border; dark input at 30% | `outlineVariant`; alpha multiplies the live token rather than replacing it |
| `rounded-lg` input/chips and popup | host `DTokens.radius` (lg factor 1.0); item md factor 0.8; chip sm factor 0.6 |
| focus 3px ring at 50%; invalid destructive 20%/40% | exterior-only annulus, live focus/destructive tokens and brightness-specific multiplicative alpha |
| popup anchor width, min anchor + 28px, max available size | measured anchor width by default, explicit width override, `DPopover` safe-boundary flip/shift collision and bounded scrolling |
| 6px popup side offset, start alignment | `DComboboxContent` defaults to bottom/start with 6 logical pixels |
| popup lg radius, foreground 10% ring, medium shadow | accepted `DPopoverContent` surface and shadow with zero inner padding |
| list max `min(252px, available - 36px)`, 4px padding | 288px outer maximum, 4px scroll content inset; the positioner further constrains to available height |
| item 28px minimum, 6px start/8px end, 8px gap | `DComboboxItem<T>` logical geometry; trailing 16px selected check |
| highlighted accent surface | live `DTokens.hover`; selected remains independently exposed by semantics and check artwork |
| group label 12/16 with 8x6 padding | `DComboboxLabel`; group semantics associate the label and options |
| empty 14px centered with 8px vertical padding | mounted live-region `DComboboxEmpty<T>` |
| chips 32px minimum, 5px/4px inset and 4px wrap gap | `DComboboxChips<T>` grows for scaled/wrapped content |
| chip 21px, muted surface, 12/16 medium text | minimum-height chip that grows at large text, host sm radius, bounded ellipsis with full semantic label |
| 100ms fade/95% zoom/8px side slide | accepted `DPopover` motion; reduced motion resolves immediately |

The registry's `ComboboxInput` is an Input Group composition and the custom row
example is an Item composition. The reviewed candidate uses the accepted
`DInputGroup`, `DInputGroupControl`, addon and button APIs, while custom results
compose passive `DItem` parts inside the Combobox-owned option target. Field
labels wrap the Combobox as metadata only; the editable input remains the sole
value, focus, Form and IME owner.

## Public behavior and lifecycle

- The ordinary and `.multiple` constructors own selection initialized once.
  `.controlled` and `.multipleControlled` display only values accepted by the
  parent, including a controlled null/empty value.
- Query can be owned internally, by a borrowed `TextEditingController`, or by a
  parent string/callback. Borrowed controllers and focus nodes are never disposed.
- An application can replace options after any async request. Selection is retained
  even if a selected value is outside the latest page; a highlight that no longer
  resolves to an enabled visible option is cleared.
- Arrow Up/Down moves through enabled filtered items and optionally loops through
  the input between list ends, matching the ARIA combobox focus model. Enter
  and the keyboard Done action select the enabled, visible highlight in both
  ordinary and chip inputs. Done leaves focus and selection unchanged when
  there is no eligible highlight, including while async results are replaced.
  Escape dismisses and restores the accepted single label.
  Pointer hover can own highlight without moving editor focus. The root's
  accepted highlighted value is the sole row-background owner, including when
  controlled by the parent. Highlight changes are immediate, matching Select;
  rows do not cross-fade or retain a separate pointer highlight when keyboard
  navigation moves to another option. Disabled options never highlight.
- The popup belongs to the editor's `TextFieldTapRegion`. A mouse press on an
  option preserves editor focus, so selection closes according to
  `closeOnSelect` without focus restoration reopening the menu. Clicks outside
  the combobox still dismiss it and leave the editor.
- Multiple selection toggles values, clears the filter and closes by default;
  `closeOnSelect: false` preserves an open rapid-entry workflow. Remove actions and
  Backspace on an empty query remove chips. From an empty editor, the
  direction-appropriate arrow key moves focus into the selected chips. Chip text
  can truncate visually at extreme scale while its full label and remove action
  remain semantic.
- Clear changes selection and query through their distinct callbacks. Form reset
  reports the mount-time initial selection/query and closes the popup.
- The accepted Popover adds an opt-out from content autofocus. Its default remains
  unchanged; Combobox uses the opt-out so the editable caret and IME stay active.
  Escape, outside press, view lifecycle, anchor removal, collision, scroll tracking,
  live inherited theme/direction/text scale and reduced motion stay Popover-owned.
- The popup pattern uses a button as the accessible form control and moves the
  input inside the popup. Ordinary input and chip patterns keep the editor itself
  as the control. Independent clear/remove actions are not merged into the editor.

## Frozen examples and acceptance criteria

The styleguide records all frozen headings without collapsing distinct catalogue
accounting: Composition, Simple, With chips, With groups and collection, Custom
Items, Multiple Selection, Basic, Multiple, Clear Button, Groups, Invalid,
Disabled, Auto Highlight, Popup, Input Group and RTL. Each mounts the real public
Combobox. The example is implemented after final-owner composition, automated
verification, official browser comparison and native macOS acceptance.

Final review completed:

1. Reconcile current accepted main, Command utilities where useful, and accepted
   Field/Input Group/Item revisions without forcing cmdk semantics into Combobox.
2. Compare official Base Nova Basic, Multiple, Groups, Custom Items, Popup, Invalid,
   Auto Highlight and RTL in matching browser states against the real macOS fixture.
3. Verify pointer, touch-sized actions, native editing/IME, keyboard navigation,
   chip deletion/navigation, Escape/outside dismissal, focus restoration, scrolling,
   narrow width, 200% text, RTL, reduced motion and live light/dark/custom tokens.
4. Run focused component, styleguide, Popover regression and adopted group-member
   tests plus root and `profiles/full` static analysis with all pins unchanged.
5. Compared the official Basic, Groups, Custom Items and Popup states in the
   browser with the isolated native fixture. Native acceptance also exercised
   single and multiple selection, chip removal, clear/focus behavior, Escape focus
   restoration, the accepted Input Group composition, Add Group Members async
   search/save, 216/320px bounds, 200% text, RTL, reduced motion and live palettes.

Automated acceptance covers the focused Combobox/styleguide/Input Group/Item/
Popover/Group Page regressions, root and full-profile static analysis, and an
exact-source macOS debug build. iOS, Linux and spoken VoiceOver behavior were not
inspected and remain explicit platform follow-up work.

## Application audit

Adopted: the Add Group Members form is a true asynchronous multiple-value
Combobox. The application controller retains debounce, request sequencing,
loading/error state, selected usernames/emails and save authority. The adapter
replaces generic options, maps custom user/avatar and email rows, and translates
typed selected values back to the existing controller. Existing keys and callback
behavior remain covered by the Group Page regression.

Retained deliberately:

- `TopicFilterInput` is a free-form query language with clause completion, token
  parsing and submission fallback; Base UI explicitly says Combobox is not a
  free-form search widget.
- Composer mention/emoji suggestions complete text at the caret and include command
  actions; they retain their editor-owned autocomplete controller and popup.
- Category, tag, assignment and time-range anchored pickers are route/sheet-adaptive
  domain surfaces with async pagination/permissions and remain for their Select,
  Command, Sheet or picker-owner reviews.
- Topic list tag filtering accepts free-form/domain query clauses rather than a
  selection restricted to one returned object.
- DSelect remains the non-editable selection owner. Command menus remain
  action selection owners, not form values.
