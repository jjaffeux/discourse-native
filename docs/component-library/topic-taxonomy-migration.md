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
- Category editing uses the shared `TopicCategorySelector`, also used by the
  topics list and composer. Its Native Combobox supplies the compact search
  field, normal-weight option rows, selected checkmark, keyboard navigation and
  content-sized popup on pointer and touch platforms. Header controls supply
  their tinted split trigger; category/subcategory removal is a selector option.
- Tag editors use `DPopover` on pointer platforms and `DDrawer`
  on touch platforms. `TopicTaxonomyPickerAnchor` is application coordination
  for the existing asynchronous result API; Native owns overlay layout,
  dismissal, focus, theme updates and touch targets.
- Tag search uses `DInput` and `DSeparator` above a bounded `DScrollArea`.
- Tag choices compose a passive `DItem` with `DCheckbox`. The checkbox's
  `secondary` slot contains the independent browse `DButton`, which stays
  active when selection is disabled or the tag limit has been reached.
  Selected tags retain both a checkmark and a muted row background. Creating
  an allowed tag uses `DButton`.
- The same editors are used by the header and property/sidebar anchors. The
  composer now shares the topics-list selectors documented in
  [Category and tag selectors](category-tag-selectors.md). The read-only
  overflow also uses Native input, scrolling and Item links. Unrelated users
  of the older anchored-picker adapter are unchanged.

No new kit API is introduced. Debounced/latest-wins search, capability checks,
parent/subcategory filtering, immediate saves, tag creation/limits, error
handling and account/topic ownership remain in the existing app adapters.

Native pointer popovers allow outside interaction, dismiss on Escape and close
when their anchor is removed. Search remains fixed while results scroll.
Touch controls retain the kit's 48px targets. Narrow compact category controls
omit their separate browse half when both touch targets cannot fit; read-only
categories retain navigation on their primary control. Tag overflow preserves
editing when the pencil cannot fit.

## Initial migration verification

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

The implementation commit is `a4ff463a`. Integration with the concurrent
composer taxonomy-button and topic-navigation work preserved `TopicTaxonomyButton`
and added Native anchors/triggers around it. The integration run passed 84
composer, header and adoption checks, plus root analysis. A further six focused
read-only/category navigation checks passed after the final link-semantics fix.

The actual macOS fixture was built with `flutter build macos --debug --no-pub
--target tool/topic_taxonomy_review_main.dart`. Its isolated ad-hoc bundle
`org.discourse.native.topic-taxonomy-review` passed deep/strict signature
verification and launched successfully. Restricted push/team/application
identity entitlements were omitted; the real app's signing settings were unchanged.
The inspected integrated kernel SHA-256 was
`276b9787f4e2c70ae16d6ebbdc22ad3c32498660f9cc9cdc39eb806a3d6112bb`.

Native inspection covered dark and light headers, category search for `todo`
and Enter selection with a changed tint, the empty subcategory list and Remove
subcategory, tag browsing with no tag save, selecting `approved`, creating
`native-review` with Enter, and selected-tag removal. Browsing changes the fake
shell route, so Restore/Reset topic returns to the topic before subsequent
editing; the normal stale-topic error guard was also observed. Plum at 320px,
200% text and RTL retained reachable category and tag-overflow controls, wrapping
menu rows, and a readable category-search error. Escape dismissed the menu.
Native AX exposed separate category edit/browse controls and tag checkboxes/browse
links. Spoken VoiceOver, iOS and Linux device sessions were not run.

The isolated app was quit using its native menu, its process disappearance was
verified, and the desktop lease was released. The Native kit's existing
styleguide/color capability evidence remains in `button-custom-colors.md`;
this review exercised the actual production header and editors.

Merged locally into `main` from the main checkout with `--no-ff`: `b0ac5fdf243c38f4df11daea7d74bea496dae2f4`.
The merge tree exactly matches the verified candidate. The later message-inbox
tab integration left every migrated taxonomy source and the native fixture
unchanged; final root analysis passed.


## Shared category selector correction

The header and sidebar now instantiate `TopicCategorySelector`, the same
component used by the topic list and composer. The old `TopicCategoryPicker`
checkbox list and separate asynchronous popup implementation are removed.
The shared selector supplies its own search field, normal-weight rows,
selected checkmark and popup that shrinks for short or empty results.
`triggerBuilder` preserves the header's tinted Native Button Group and its
independent browse action. Removal reuses the existing `clearSelectionLabel`
API added by the concurrent composer subcategory change.

The editor keys each selector by the account session, topic and category scope.
Replacement removes the popup and retires its lookup. Captured callbacks,
late search results and completed saves cannot mutate a replacement topic or
clear a newer save. Root-only and parent-specific search, configured category
icons, immediate persistence and current error toasts remain covered.

Implementation `8ec0305c` was integrated with the concurrent composer
subcategory and topic footer changes as `9024214f`. All 161 focused tests passed
across the nine affected test files recorded in `progress.json`; root
`flutter analyze --no-pub` reported no issues. Coverage includes keyboard
selection and focus restoration from a custom trigger, compact empty/removal
menus, stale account/topic callbacks, current errors, independent browsing,
320px/200% layouts, shared composer filters and the selector styleguide.


Native inspection exposed a focus bug during asynchronous subcategory removal:
Combobox could refocus its closing search input, reopen the popup, and then
notify its owner during the saving-state rebuild. `0f033b3a` fixes the existing
closing policy by leaving focus restoration to Popover when `closeOnSelect`
is true. The generic Combobox regression and the real header fixture regression
cover selection after input blur, category saving, repeated palette changes,
320px layout and 200% text. The local fixture now uses `DScrollArea`, matching
the scrolling reader when enlarged preview content exceeds its window.

Final verification passed 219 distinct tests across 13 affected files, including
Combobox, its styleguide and group-page consumers. The fixture test's platform
setup uses the runner's native platform variant. Root analysis is clean.


The final candidate `317dfd0` also preserves the concurrent Combobox
`TextFieldTapRegion` pointer fix and topic-list scrolling changes. All 105
integration checks passed, and root analysis reported no issues.

The final native macOS review used the real production header in the isolated
ad-hoc signed bundle `org.discourse.native.topic-category-selector-ready`, built
with `flutter build macos --debug --no-pub --target
tool/topic_taxonomy_review_main.dart`. The permitted debug entitlements were
read back, deep/strict signature verification passed, and the app launched.
The inspected kernel SHA-256 is
`f815d798e0be7ee4563f1b89fd2442d254f77725d95dad4df1e1eddb11aa1268`.

CUA confirmed the compact normal-weight category rows and selected checkmark,
filtering to `todo` and saving with Return, the light empty subcategory menu and
mouse removal, and the formerly failing palette change after saving. Plum at
320px with 200% text and RTL preserved the reachable selector, wrapped the long
urgent category label, and displayed a compact readable search error. Escape
closed the popup. The category save count advanced exactly once per selection;
separate browse links remained exposed in native accessibility output.

The isolated app was quit, process disappearance verified, and the desktop
lease released. No production account data was used. Native device evidence
is macOS only; iOS/touch coverage is from widget tests.

Merged from the main checkout into local `main` with `--no-ff`: `8b910d2acd59240dffa57eb6624ee286e42d467e`.
The merge tree exactly matches the verified candidate.
