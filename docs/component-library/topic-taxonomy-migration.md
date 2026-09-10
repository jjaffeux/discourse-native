# Topic category and tag controls

This follow-up migrates the production controls from the user's four topic
header screenshots. The earlier custom-color Button work supplied the kit
capacity; this change adopts it in the application.

## Production composition

- Both expanded and compact topic headers use `DButtonGroup` with a category
  button and a separate browse link. The category color supplies the same 10%
  fill, 25% outline and 8% hover overlay blend. Configured category icons,
  private-category markings, loading and independent navigation remain.
- Visible tags use `DBadge.link`; the overflow uses `DBadge.action`. The pencil
  and empty-tag action use `DButton`. Clicking a tag still navigates, and the
  pencil/overflow opens editing. Middle-click navigation remains independent.
- Category and tag editors use `DPopover` on pointer platforms and `DDrawer`
  on touch platforms. `TopicTaxonomyPickerAnchor` is application coordination
  for the existing asynchronous result API; Native owns overlay layout,
  dismissal, focus, theme updates and touch targets.
- `DInput` and `DSeparator` stay above a bounded `DScrollArea`. Category choices
  use `DCheckbox`, configured category icons and parent-path labels. The
  remove-category/subcategory action uses `DButton`.
- Tag choices compose a passive `DItem` with `DCheckbox`. The checkbox's
  `secondary` slot contains the independent browse `DButton`, which stays
  active when selection is disabled or the tag limit has been reached.
  Selected tags retain both a checkmark and a muted row background. Creating
  an allowed tag uses `DButton`.
- The same editors are used by the header, property/sidebar anchors and the
  composer. The read-only overflow also uses Native input, scrolling and Item
  links. Unrelated users of the older anchored-picker adapter are unchanged.

No new kit API is introduced. Debounced/latest-wins search, capability checks,
parent/subcategory filtering, immediate saves, tag creation/limits, error
handling and account/topic ownership remain in the existing app adapters.

Native pointer popovers allow outside interaction, dismiss on Escape and close
when their anchor is removed. Search remains fixed while results scroll.
Touch controls retain the kit's 48px targets. Narrow compact category controls
omit their separate browse half when both touch targets cannot fit; read-only
categories retain navigation on their primary control. Tag overflow preserves
editing when the pencil cannot fit.

## Verification

- Formatting, `git diff --check`, and root `flutter analyze --no-pub` passed.
- 151 focused tests passed across `topic_tag_picker_test`,
  `topic_picker_anchor_lifecycle_test`, `composer_picker_modal_test`,
  `topic_inbox_test`, `topic_taxonomy_fields_test`,
  `topic_title_field_ownership_test`, `topic_header_tags_test`,
  `anchored_picker_test` and `d_button_adoption_test`.
- Coverage includes immediate selection/removal and reopening, disabled
  choices at the tag limit, independent keyboard and middle-click browsing,
  search staying fixed during long-list scrolling, category icons/path labels,
  stale searches/saves across account and topic replacement, current errors,
  read-only navigation, narrow layouts and enlarged text. iOS platform
  overrides exercise Native drawers and touch geometry in widget tests.
- Harnesses now mount the app's `DToaster` for current save-error assertions,
  allow OverlayPortal's mount/results frame, and dismiss popovers away from
  unrelated actions. Geometry checks now respect Native touch targets.
- `tool/topic_taxonomy_review_main.dart` mounts the real `TopicInboxHeader`
  with fake stores and API responses, including searchable sales/deals
  categories and discovery tags. It supplies palette, width, text scale,
  direction, empty-result and search-error controls without account writes.

Native review and local merge evidence will be recorded after execution.
