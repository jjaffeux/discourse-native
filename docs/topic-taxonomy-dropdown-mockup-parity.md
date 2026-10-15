# Topic-list category and tag dropdowns

Reference: `discourse-native-mockups` commit
`37001839df3efbeb5f2650668a38140462ce9c45`, specifically `CategoryPath`,
`FilterSheet`, `FilterOption`, and `tagPillLabel` in `src/App.tsx`.

- Each category breadcrumb opens its own sibling level. The menu browses
  children separately from selecting the whole category, shows ancestry for
  search results, and displays category counts from the forum's data.
- Exact category selection has an explicit "No subcategories" breadcrumb.
  Selecting another category replaces exactness. Backspace removes exactness,
  then ancestry; a shortened path retains the editor on its remaining segment.
- Scoped menus show only their own filter chips, hide the syntax prefix, and
  use category/tag search placeholders. Category selection closes immediately;
  tag choices and matching modes update the list while their menu stays open.
  Other category, tag, and advanced clauses remain intact.
- Tags retain usage order, one checkbox per selection, four matching modes,
  and a Done row. Pills describe single, multiple, excluded, group, and special
  tag scopes. Group and special choices depend on the server's vocabulary.
  The approved Native compact checkbox preset is 14px, with matching hit bounds.
  Native toggle groups wrap the matching modes as text grows, preserving their
  selection and keyboard navigation.
- Desktop menus remain inside their owning pane; phones use the Native
  adaptive menu sheet and wait for an explicit request to focus the input.
  Escape clears a search first, then dismisses. This uses the approved Native
  `DPopover.onEscape` hook.
- Feed, tab, forum, account, and session replacements retire the editor and
  pending lookups. Live choices may replace only their own feed; they cannot
  adopt a different navigation context.

The focused widget tests exercise the production shell and fake API contracts.
Real-font captures cover desktop/phone, Standard/Liquid Glass, light/dark, and
200% text. These are widget renders, including the test renderer's glass
fallback, rather than physical-device captures. Set `SIDEBAR_FILTER_REVIEW_DIR`
when running `test/topic_taxonomy_dropdown_parity_test.dart` to export PNGs.
