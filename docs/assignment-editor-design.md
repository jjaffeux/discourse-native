# Assignment editor design and implementation

Use a **centered Dialog on desktop and a bottom Drawer on mobile**. Assignment
is a short form: choose one assignee, optionally add context, then submit.
The current anchored picker makes the form look like a menu and gives the
assignee list only 180 logical pixels of height.

The HTML/CSS study includes three working presentations, local search, single
selection, people and groups, a note, optional statuses, submission feedback,
empty results, a save-error state, and editing/unassigning. Sample data and writes
stay inside the preview. Initials stand in for the application's real avatars.

## Presentations

| Design | Composition | Best use |
| --- | --- | --- |
| A — Focused dialog, recommended | 480px maximum width; title and short instruction; search above visible radio choices; collapsed optional note; separate footer | Routine assignment on desktop |
| B — Side sheet | 400px at the logical end; fixed header/footer; scrolling body; note always visible | Workflows where a longer handoff note is common |
| C — Bottom drawer | Full available width; swipe handle; scrolling choices; optional note; full-width primary and Cancel actions | Narrow/touch layouts |

Use the kit's existing responsive Drawer/Dialog composition, which uses 768px
as its example breakpoint, as the implementation starting point. Keep one
application-owned draft when changing presentation. Do not dismiss and discard
the draft during a resize. The side sheet is a modal alternative; the visible
topic behind it remains inert. It does not promise simultaneous topic interaction.

## Exact Native component mapping

Import application UI from `package:discourse_native/discourse_ui.dart`.
The implementation uses the components below. The user approved the optional
live dismissal guard added to the imperative dialog/drawer helpers.

| Part | Existing API | Composition / behavior |
| --- | --- | --- |
| Desktop container | `showDDialog`, `DDialogContent(maxWidth: 480)` | `DDialogHeader`, `DDialogTitle`, `DDialogDescription`, `DDialogFooter`, `DDialogClose`. The route owns modality, Escape and focus restoration. |
| Side sheet alternative | `DSheet`, `DSheetContent(side: DSheetSide.end, sidePanelWidth: 400, sidePanelMaxWidth: 400)` | `DSheetHeader`, `DSheetTitle`, `DSheetDescription`, `DSheetBody`, `DSheetFooter`, `DSheetClose`. Use logical end for RTL. |
| Mobile container | `showDDrawer(showSwipeHandle: true)`, `DDrawerContent` | `DDrawerHeader`, `DDrawerTitle`, `DDrawerDescription`, `DDrawerScrollArea`, `DDrawerFooter`, `DDrawerClose`. Use its keyboard/safe-area and gesture ownership. |
| Search | `DField`, `DFieldLabel`, `DFieldControl`, `DInputGroup`, `DInputGroupInput`, `DInputGroupAddon` | Visible “Assign to” label; search icon in the inline-start addon; hint “Search users or groups…”. Retain the existing debounce and stale-response protection. |
| Assignee selection | `DRadioGroup<String>.controlled`, `DRadioGroupItem(card: true)` | One controlled selection using a stable user/group key. Compose avatar and two-line identity inside the item's `label`; optional group badge in `trailing` (stacked under the identity for narrow/large-text layouts). The item owns whole-row activation, radio semantics, keyboard focus and selected styling. Do not wrap it in another clickable row. |
| Identity | `DAvatar`, `DItemContent`, `DItemTitle(maxLines: null)`, `DItemDescription(maxLines: null)` | Reuse the application's assignee/avatar adapter for actual image and fallback data. Plain Flutter Row/Column/Expanded layout is composition, not a second control. |
| Group identification | `DBadge` | “Group” text distinguishes a group without relying on the avatar or color. Use the existing outline variant. |
| Scrolling | `DScrollArea`, plus each presentation's body/scroll helper | Give the result list bounded room. Preserve the title/search and submission actions; let the form body scroll when the note, large text or keyboard needs space. Use the shared scroll owner instead of copying its scrollbar. |
| Optional note | `DCollapsible`, `DCollapsibleTrigger`, `DCollapsibleContent(keepMounted: true)`, `DField`, `DFieldLabel`, `DFieldControl`, `DTextarea` | “Add a note” expands the editor. Keep its text when collapsed. Start expanded when editing a nonempty note; the side sheet always exposes it. The trigger takes passive content, not a nested DButton. |
| Optional status | A separate `DRadioGroup<String>.controlled` and `DRadioGroupItem` labels | Show only when the site's assignment statuses are enabled and nonempty. Use the actual status values, including an existing value no longer advertised. The preview's Open/In progress/Done are fixtures. Wrap short sets; use a vertical radio list for long labels or larger sets. |
| Primary / secondary actions | `DButton` | Primary “Assign to @username” / “Save changes”, outline Cancel, and the existing destructive variant for Unassign in edit mode. Use `loading` for submission and nullable callbacks to disable unavailable actions. |
| Loading / failures / empty state | `DSkeleton` or `DSpinner`; `DProgress`; `DAlert`; `DEmpty` family; `DButton` | Initial suggestions loading, background search progress, an inline failure with Retry, and “No matching users or groups”. Keep these distinct from each other. |
| Completion | Existing assignment detail `DItem`; optional `DToast` | Close only after successful save and update the topic's assignment detail. A toast can confirm completion. |

## Interaction decisions

- **Single selection:** `AssignmentSave` currently accepts one
  `AssignmentAssignee`. The screenshot's square selection indicators are
  misleading for that model. Radio choices communicate the actual behavior.
  A future multiple-assignee feature would require a separate product/data decision.
- **Selection is a draft:** selecting a person does not close or submit the
  editor. The primary action names the selected user or group. Nothing is
  preselected when creating an actual new assignment; the preview opens in a
  selected state to show the design.
- **Search does not erase selection:** if the selected assignee is outside the
  current results, retain it and show “Selected: @username”. Keep the explicit
  primary label visible. Preserve the current prohibition on saving while a
  server search is unresolved.
- **Draft lifecycle:** Cancel, Close, Escape and an allowed outside press discard
  unsaved edits. Reopening an existing assignment loads its saved assignee,
  note and status. A failed write retains the current draft and displays an
  inline error. Retrying must not require choosing the assignee again.
- **Write ownership:** retain `beginPicker`, `isPickerCurrent`, service identity
  checks, queued-search epochs and the mounted/session guards from the existing
  editor. Coalesce submission, disable controls while saving, and prevent all
  dismissal paths—including drawer drag—while the write owns the target.
  Adapt the controller's nullable error result before using a helper that
  automatically closes on a resolved Future: an error string is not success.
- **Keyboard and accessibility:** focus search on desktop; on mobile let the
  drawer open without immediately covering suggestions with the keyboard.
  Use the radio group's arrow/Space behavior and do not make Enter submit
  merely because a radio is focused. Retain kit focus restoration, touch bounds,
  large-text growth, RTL and reduced motion.
- **Visual tokens:** the purple in the mockup comes from the supplied screenshot.
  Production uses `DTokens` from the site's palette, `DSpacing`, existing
  typography, and `DControlSize.regular` / `large`. Do not copy preview CSS
  swatches or override individual control padding, height or radius in Flutter.

## Source references checked

- [Current editor](../lib/src/plugins/assign/assignment_sheet.dart)
- [Public UI entrypoint](../lib/discourse_ui.dart)
- [Conventions](component-library/conventions.md) and [catalogue](component-library/catalogue.json)
- [Dialog examples](../lib/src/styleguide/examples/dialog_examples.dart): Edit profile, Sticky Footer, Scrollable Content
- [Drawer examples](../lib/src/styleguide/examples/drawer_examples.dart): Delivery time, Responsive dialog, Swipe handle
- [Sheet examples](../lib/src/styleguide/examples/sheet_examples.dart): Scrollable body, RTL
- [Radio Group examples](../lib/src/styleguide/examples/radio_group_examples.dart): Choice Card, controlled form, dynamic options
- [Input Group examples](../lib/src/styleguide/examples/input_group_examples.dart): Default search
- [Collapsible examples](../lib/src/styleguide/examples/collapsible_examples.dart): Settings Panel with keepMounted
- [Field examples](../lib/src/styleguide/examples/field_examples.dart): Input, textarea and select

## Implemented behavior

- Desktop opens a centered dialog; viewports below 768 logical pixels open a
  bottom drawer. The opening presentation remains mounted for the route's
  lifetime, preserving the draft and asynchronous operations during resize.
- Search, single selection, optional note, configured status, assignment and
  unassignment use the Native controls above. Existing values and drafts survive
  search, note collapse, failed writes, and presentation resizing.
- The header/search and footer are normally fixed. On the drawer, the header
  joins the scroll region when large text or the keyboard reduces available
  space. Failed writes scroll the error into view for retry.
- `showDDialog` and `showDDrawer` accept an optional `canDismiss` callback.
  Each close, controller close, Escape, back, outside press and drawer swipe
  checks its current value. A denied swipe rebounds. Assignment blocks dismissal
  while saving or unassigning. Explicit Navigator route removal still supports
  session teardown. Existing helper callers retain their default behavior.
- Drawers opened with `requestInitialFocus: false` now measure their swipe
  surface and focus only the modal scope, preserving Escape dismissal without
  focusing the search field or requesting a software keyboard.
- Both component styleguide pages include a runnable **Guarded helper dismissal**
  example. `tool/assignment_review_main.dart` mounts the production form with
  in-memory fixtures for review without account requests.

## Verification

All **128** focused assignment, session-boundary, plugin, modal-helper and
styleguide tests passed. `flutter analyze --no-pub` reported no issues, formatting
and `git diff --check` passed, and the local-data macOS debug build succeeded.
The checks cover selection, metadata, errors, retries, stale searches, account
replacement, pending-write dismissal, focus entry/restoration, swipe rebound,
resize preservation, search focus while the keyboard moves the header, and
narrow 200% RTL layout with simulated keyboard insets.

Native review used an isolated macOS debug bundle of the local-data fixture,
with the production editor and modal helpers. Checked desktop dialog and mobile
width drawer, light/dark palettes, saved notes, optional statuses, 200% text,
RTL, scrolling, save success/failure and Escape during a pending save. No real
account data was changed. The mobile-width macOS review and Flutter inset tests
are not iOS/Android device or simulator testing; spoken VoiceOver was not run.

The final fixture rebuild launched, but native actions then stopped responding
(`noWindowsAvailable` and launch timeout from the desktop inspection tool).
The final header-scroll, identity-wrap, note-wrap and error-reveal adjustments
passed the focused widget suite; a native recheck of those adjustments and the
new guarded styleguide examples remains unverified. The earlier native checks
above apply to the preceding build, not a claimed final native acceptance.
