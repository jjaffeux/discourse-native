# Bookmarks page layout

The September 22 references use a full-width list with a page heading and
left-aligned type filter. Bookmark rows show a circular target icon, a wrapping
title and a muted type/category or channel subtitle. The site palette supplies
colors; Native Item, Avatar, Select and Separator own the controls and states.
The compact user-menu section retains its own presentation.

Post and topic metadata uses the serialized category ID. Chat supplies its own
presentation through a plugin capability, including channel identity and the
current account's “you” label. Filters retain the existing bookmark feed and
navigation behavior. The existing twenty-row user-menu feed limit is unchanged.

Verified on September 22, 2026:

- Static analysis: no issues.
- 176 focused tests passed, covering bookmark parsing, API/controller/editor
  behavior, the new page, keyboard semantics, activity lifecycle, user-menu
  identity, mobile shell navigation and plugin dependency boundaries.
- 46 page/mobile-shell tests passed on the integration candidate.
- Rendered the production page at 390px and 1080px, checked left alignment,
  wrapping, filters, empty/error states, 320px RTL and 200% text.
- Built and launched an isolated macOS debug fixture. Inspected the actual page
  at desktop and 390px phone widths, dark/light palettes, native accessibility
  labels and the Chat filter. Compared the existing Native Select styleguide.
  Phone mode used iOS control density and 120% text; this was a macOS preview,
  not an iOS or Android device run.
