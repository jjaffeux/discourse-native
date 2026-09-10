# Category and tag selectors

`TopicCategorySelector` and `TopicTagSelector`, exported by
`package:discourse_native/discourse_ui.dart`, own the complete selection control:
the button, search field, popup, options and selection indicators. The topics
list and topic composer instantiate these same components. Topic header and
sidebar category editing also use `TopicCategorySelector`. Callers supply data,
permissions and controlled selection callbacks.

These are application compositions in `lib/src/shell/`, built from Native
Combobox and Button. They appear as **Category selector** and **Tag selector**
in the styleguide through `application_component_catalogue.dart`. The frozen
upstream component catalogue is unchanged.

- Category filters search their local categories and can expose All categories
  or All subcategories. The composer supplies asynchronous, permission-filtered
  category search and full parent-path labels. It also uses a second instance
  for the selected parent's creatable subcategories, filtered locally like the
  topics list. Selecting a child keeps the parent and child in separate controls.
  `clearSelectionLabel: 'No subcategory'` restores the parent when posting there
  is allowed. Changing either value rechecks the category's tag requirements.
- Header categories supply `triggerBuilder` to retain their tinted Native
  Button Group and independent browse link. `clearSelectionLabel` adds a null selection
  for removing a subcategory or moving to Uncategorized; callers resolve the
  destination. It remains reachable while searching, including loading/error
  states. An empty search does not implicitly select removal in place of the
  current category.
- Tag filters support single or multiple selection, All tags and known-tag
  fallback. The composer supplies category-scoped search, selected tags and
  creation/limit capabilities. Selected tags remain available for removal.
- Searches reset on reopen and ignore retired results immediately when the
  query changes, the popup closes or the widget is disposed. Change the
  selector's key when its account or search scope changes; the composer keys
  tag selection by composer and category.
- The Native Combobox owns keyboard navigation, focus, popup placement and
  dismissal on both pointer and touch platforms.

The styleguide has interactive filter, composer and disabled examples. Composer
examples include asynchronous search, empty/error states, subcategory labels,
tag creation, disabled tags and a two-tag limit. All data stays local.

## Verification

- `dart analyze`: no issues.
- 94 focused widget tests passed with random seed `927614`: shared selectors,
  styleguide entries/layout, composer dropdowns, list filters/menu ownership and
  composer tag search. The selector examples also pass at 320px with 200% text.
- A debug macOS fixture mounted the real `TopicListFilterBar`, `ComposerPanel`
  and styleguide. Inspected list/composer category and tag dropdowns in dark and
  light palettes, with 700px and 320px content widths. Exercised category
  selection, tag addition/removal, multiple selections and Escape dismissal.
- Opened both styleguide pages natively, changed the category, inspected disabled
  tag options, and created a tag with search and Enter. The isolated app launched
  with permitted debug entitlements and was quit after review.
- Native evidence is macOS only. Touch behavior and 200% text were covered by
  widget tests, not device testing.

The inspected implementation is `1eedd7db`. Integration started from main
`af31034e` and preserved the same selector, composer, filter and styleguide
source, including the underlying Native Combobox and Button. Composer conflicts
were resolved in favor of the complete shared selectors; header/property picker
migrations remain intact. All 140 integration tests passed, including the above
checks plus picker-anchor lifecycle, topic-header tags, taxonomy fields and
button adoption. Root analysis remained clean.

Merged locally into main from the main checkout with `--no-ff`:
`44becaad5af517e9c34bbd00debe82af84108ada`. The merge tree matches the tested
integration candidate exactly.

## Composer subcategories follow-up

The composer now shows the shared subcategory selector for parents with known
creatable children, including an already selected child. The parent menu keeps
full-path search so children of parents that cannot accept topics remain
reachable. Replacing the parent retires the child popup; the actual selected
child ID remains the draft/submission category and the tag-search scope.
The Composer categories styleguide example demonstrates the paired controls.

All 98 focused tests passed with seed `38126`, including selection/clearing,
parent switching, popup retirement, posting permissions, tag revalidation and
requirements, narrow composer geometry, and both styleguide controls at 320px
with 200% text. Root `dart analyze` reported no issues.

The real composer and updated styleguide were inspected in an isolated macOS
debug fixture. Native checks covered searching a subcategory and selecting it
with Enter, restoring the parent, changing parents and selecting another child,
Escape dismissal, and a light 320px layout as well as the dark wide layout.
The styleguide's subcategory choice updated independently of its parent. The
app was quit and the desktop lease released after review. Enlarged text and
touch-platform behavior were widget tests, not device sessions.

The follow-up implementation is `59e4b4e6`, merged from the main checkout with
`--no-ff` as `a5d1bbb11b5af9b8bf08a530a7d5a6b106bc1644`. The merge tree exactly
matches the tested source.

## Close after mouse selection

A desktop mouse press blurred the popup's search input before selecting an
option. The combobox then restored input focus, which immediately reopened the
dropdown. Mouse regressions reproduced this for both local and asynchronous
category searches, including choosing the already selected category.

The shared Native Combobox now includes its popup in the editor's
`TextFieldTapRegion`. Option presses retain focus and honor `closeOnSelect`;
outside clicks still dismiss and blur. All 133 focused Combobox, Popover,
styleguide, category/tag selector, composer and topic-list tests passed with
seed `69318`. Root `dart analyze` reported no issues.

Implementation `b80f71a9` was built into an isolated macOS debug fixture mounting
the real composer, topic-list filters and styleguide. Actual mouse clicks closed
the composer's category menu when reselecting its current category and when
changing parents, and closed the subcategory menu after choosing a child. The
topic-list and styleguide category menus also closed after mouse selection.
Reviewed dark 700px and light 320px content layouts. The app launched with
permitted debug entitlements, was quit, and the desktop lease was released.
Native evidence is macOS only.

Integrated from main `759916ca` while preserving its category-heading tooltip
removal. The Combobox, selectors, composer, filters, styleguide and focused tests
match the inspected implementation. Merged locally from the main checkout with
`--no-ff` as `9bac0c36899566fad4a85341039133ded3995fcf`; its tree exactly matches
integration candidate `bea87496`.
