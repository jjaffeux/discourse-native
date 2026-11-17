# Assignment parity

Source: `discourse-native-mockups` commit `540cbac` on `test-mobile-layout`,
the phrases "assigning from a shortcut at a topic's foot, every assignment
listed there, people and groups picked as recipients are, in one press".
Line numbers cite the saved diff of that commit on `src/App.tsx`
(`c1-app.diff`); the end state is the tip `ab471b3`. A post's news lines, the
foot's tool pill and `SheetSearch` come from the slices documented in
`post-news-and-share-mockup-parity.md`,
`topic-foot-and-dock-toasts-mockup-parity.md` and
`scrollbars-and-sheet-search-mockup-parity.md`.

## Checklist

| Mockup change | Evidence | Native | Verified by | State |
| --- | --- | --- | --- | --- |
| Who something is given to is picked as who a message goes to is: people and, unless only a person will do, groups; the one pressed is the choice, with no confirm button | app 351–406 (`PersonSheet`), 1843–1947 (`RecipientsPicker` `onPick`, `chosen`, `groups`) | `showPersonPicker` in `lib/src/shell/person_picker.dart`, exported through the plugin SDK: `SheetSearch` over `DItem` rows (22 face, handle · name), groups as quiet pill chips with their member count where known, at the sheet's foot on a phone and over the people on a desktop. A press closes it with the pick | `topic_change_owner_ownership_test.dart`, `assign_shell_controller_test.dart` "reassigns in one press…" | Done |
| The one it is already with is shown as chosen | app 1904–1931 (`isChosen`) | `chosen` draws the row selected (strong neutral fill and the kit's check); a chosen group chip is `quietSelected` | `assign_shell_controller_test.dart` | Done |
| On a phone the sheet opens on its field, placeholder "Assign topic to…", "Reassign topic to…", "Assign post to…", "Change owner to…"; on a desktop the note stays above and the placeholder is "Search users or groups" / "Search users" | app 380–395 | `showShellSheet(search: true, dialogOnDesktop: true)`; the note only off a phone | `topic_change_owner_ownership_test.dart` (both), `topic_head_mockup_parity_test.dart`, `mobile_topic_layout_test.dart` | Done |
| Change owner, for one post and for picked posts, uses the same picker with no groups | app 621–638, 1132–1146 | `showTopicChangeOwner` opens the picker with `groups: false`; the write follows the press from the target captured at opening. A refusal or uncertain write is toasted with the post-mutation feedback, which carries Refresh | `topic_change_owner_ownership_test.dart` (43), `post_mutation_outcome_test.dart`, `topic_actions_integration_test.dart` | Done |
| The first post's menu offers "Assign topic", or "Reassign topic" and "Unassign from topic"; other posts keep "Assign post" / "Unassign from post" | app 435–490 | `AssignPlugin.postMenu`, all in the overflow | `assign_plugin_test.dart` "the first post assigns the topic from its menu", `assign_shell_controller_test.dart` rebuild isolation | Done |
| The topic's assignment is news on the first post, its mark the assignee's face (a group's mark for a group), its action the pencil | app 784–844, 2072–2105 (`Face`) | `AssignPlugin.postHeaders`: `DAlert.postNotice` with `AssignmentAssigneeAvatar` at 30 (a group draws `GroupFace`), "Topic assigned to NAME", `AssignmentEditButton` as its action | `assignment_mockup_parity_test.dart`, `assign_plugin_test.dart` | Done |
| The pencil opens Reassign and Unassign | app 1229–1265 (`AssignEdit`) | `AssignmentEditButton`: a post-action ghost pencil opening a `DDropdownMenu` with "Reassign topic/post" and "Unassign NAME from topic/post", plus the note and status route below | `assign_plugin_test.dart` | Done |
| A post's assignment is a note box after what it says and before its controls: primary at 6%, radius 10, padding 8, reaching 8 past the column, a 36 face, "Post #N assigned to NAME" at 13 secondary over the handle at 12.5 muted, the pencil | app 491–506 (`NOTE_BOX`), 922–940, 1185–1228 | `PostAssignmentNote` from `postDecorations`, on the new `DItemVariant.note` | `assignment_mockup_parity_test.dart` (box after the body, 8 past it, 36 face), `assign_plugin_test.dart` (sizes, text sizes, pencil inside) | Done |
| The shortcut at the topic's foot on a phone, beside the bookmark and the bell, showing the face of whoever has the topic at 18 or the assign icon; label "Assign topic", "Assigned to NAME" or "N assignments" | app 1287–1338, 1588–1603 | `TopicPropertySection.compactAction` with empty `actions`, so the host puts it in the pill | `topic_compact_actions_sheet_test.dart`, `mobile_topic_layout_test.dart`, `topic_head_mockup_parity_test.dart`, `assign_plugin_test.dart` "the foot shortcut says…" | Done |
| Pressed with nothing assigned it picks; otherwise a sheet "Assignments" lists every assignment, the topic first then each post in order | app 1266–1286, 1328, 1339–1341 | `onSelected` only with nothing assigned; otherwise the host opens the section's details, whose values are the rows, read from the topic record the stream already holds (no request per post) | `assign_plugin_test.dart` "orders rows…", `topic_compact_actions_sheet_test.dart` | Done |
| Each row: 36 face, "Assigned topic to" / "Assigned post #N to" at 12 muted over the name at 14 semibold, a round 36 pencil to reassign and a round 36 unassign in the danger tone at 18%, rows ruled off | app 1342–1419 | `_TopicAssignmentRow`: `DItem`, `DButton.iconOnly` at the filter size (36 on a phone) in pill shape, the unassign the destructive variant with the danger tone at 18% as its fill; `DSeparator` between rows | `topic_compact_actions_sheet_test.dart`, `assign_plugin_test.dart` | Done |
| An "Assign topic" row at the end when only posts are assigned | app 1420–1450 | The last value, ruled off | `assign_plugin_test.dart` | Done |
| The list is put away before the picker opens | app 1384–1388, 1424–1427 | `pickAssignee(before:)` with `DPopoverClose.maybeOf` | `topic_compact_actions_sheet_test.dart` | Done |
| Assigning leaves the phone's topic actions sheet | app 1104–1130 | The section has no `actions` | `topic_compact_actions_sheet_test.dart`, `topic_head_mockup_parity_test.dart` | Done |
| Toasts: "Assigned topic to NAME", "Assigned to NAME", "Unassigned from topic", "Unassigned", "Unassigned from post #N" | app 653, 667, 1299–1307, 11589–11593 (tip) | `pickAssignee` and `unassignAssignment` in `assignment_actions.dart`; unassigning keeps its Undo | `assign_shell_controller_test.dart` (topic assign, topic and post unassign); the post wordings by reading | Done |
| Change owner toasts "Owner changed to NAME" | tip 11680 (earlier mockup state) | Toasted on a fresh accepted write | `topic_change_owner_ownership_test.dart` | Done |
| `Face` for a group: the group icon at half size on the raised surface in the muted colour | app 2076–2105 | `GroupFace` in `person_picker.dart`; `AssignmentAssigneeAvatar` draws it for groups | `assign_plugin_test.dart` | Done |

## Calls made

- **Who assigned it.** The mockup says "You assigned this topic to NAME"
  because its only viewer is the assigner. Topic payloads name the assignee,
  not who assigned, and the app shows assignments made by anyone, so the
  line says "Topic assigned to NAME", the same shape as the note box's
  "Post #N assigned to NAME".
- **Note and status.** The one-press picker has no room for the assignment's
  note or, where `enable_assign_status` is on, its status. A reassignment
  carries the existing note and status to the new assignee, and the pencil's
  menu keeps the full form as "Edit note and status" (or "Edit note" / "Add a
  note" without statuses). A new assignment is made without a note; one is
  added from the pencil afterwards. When a note or status is set, it is said
  under the news line and in the note box, which the mockup does not draw.
- **Where the shared picker lives.** Change owner is the shell's, so the
  picker is in `lib/src/shell/person_picker.dart` and the Assign plugin
  reaches it through `discourse_plugin_sdk.dart`.
- **Errors after one press.** The picker closes on the press, so a write that
  fails is toasted rather than said inline. For change owner this is the
  existing post-mutation feedback, whose Refresh replaces the dialog's
  recovery button. A write whose page has since changed is not announced, as
  for every other post mutation.
- **Opening an assigned post from the list.** Rows for post assignments stay
  links to their post, as the app had them; the mockup's rows are not
  pressable but nothing in them takes the press.
- **The foot pill at 320 points and 200% text.** With the third part the
  tools take a line to themselves and the count moves under them. They stay
  inside the corner's 8-point inset.

## Kit changes

- `DItemVariant.note`: the text colour at 6% under the item, no edge, the
  standard shape's 10 corners. Needed by the post's note box (`NOTE_BOX`).
  Kit test in `test/d_item_test.dart`; styleguide: the Item page's Variant
  example. No other caller changes.
- `DPopoverClose.maybeOf(context)`: the nearest popover's close, or null.
  Needed so the Assignments list, which the desktop sidebar also shows
  outside any popover, can put its sheet away before opening the picker.
  Kit test in `test/d_popover_test.dart`.

## Not done

- The mockup's picker pages its people 30 at a time as the end is scrolled
  to. The app's lookups return a handful (Assign's suggestions are at most
  six people, and search answers a page), so there is nothing to page.

## Evidence

```sh
ASSIGNMENT_RENDER_DIR=$PWD/docs/assignment-mockup-parity \
  flutter test test/assignment_mockup_parity_test.dart
flutter test --dart-define=TOPIC_COMPACT_CAPTURE_DIR=<dir> \
  test/topic_compact_actions_sheet_test.dart
```

`assignment-mockup-parity/assigned-*.png` show the first post's news and a
post's note box on a light and a dark phone and a light desktop;
`assignments-sheet-phone-dark.png` is the foot shortcut's list (the
compact test's `assign-390-1.0`). They are widget-test renders, not device
runs.
