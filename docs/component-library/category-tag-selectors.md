# Category and tag selectors

`TopicCategorySelector` and `TopicTagSelector`, exported by
`package:discourse_native/discourse_ui.dart`, own the complete selection control:
the button, search field, popup, options and selection indicators. The topics
list and topic composer instantiate these same components. Callers supply data,
permissions and controlled selection callbacks.

These are application compositions in `lib/src/shell/`, built from Native
Combobox and Button. They appear as **Category selector** and **Tag selector**
in the styleguide through `application_component_catalogue.dart`. The frozen
upstream component catalogue is unchanged.

- Category filters search their local categories and can expose All categories
  or All subcategories. The composer supplies asynchronous, permission-filtered
  category search and full parent-path labels.
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
