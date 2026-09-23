# Users page reference alignment — 2026-09-23

The supplied users-page screenshot defines the page composition: Users heading,
compact wrapping filters, an inset separator, and an edge-to-edge user table.
The user explicitly approved adding the missing borderless Native table variant.

The page now uses that variant, 186px identity/name columns, a 132px minimum
metric column, neutral metric bars, and username initials as avatar fallbacks.
The toolbar retains searchable groups and the shared control sizes. Period and
group fields grow with text scaling; longer period labels get additional width.
The ready-state refresh action is removed; error states offer Retry, and refreshing
existing rows shows inline progress. Resizing, persistence, server sorting,
column visibility and lazy scrolling remain owned by the existing table.

Verification:

- 73 tests passed across users_page_test, users_navigation_test,
  d_data_table_test and d_data_table_soft_header_test.
- Static analysis of all seven touched Dart files: no issues.
- Native macOS debug fixture: tool/users_table_review.dart, Flutter 3.47.4,
  Skia/Metal. Inspected light wide and dark 488px layouts, 100% and 200% text,
  selected All time and verified its complete label, and inspected borderless,
  soft-header and standard styleguide examples together.
- Widget coverage includes search, period/group selection, column visibility,
  resizing and width persistence, sorting, scrolling, pagination, loading,
  error retry and the single-row desktop toolbar at 488px. The compact toolbar
  test loads bundled Lato into Roboto to avoid Ahem's artificial glyph widths.
- Independent review identified long period label clipping; the final layout
  provides wider fields for those labels and scales field widths with text.

Native checks used offline fixture data and the application theme. The screenshot's
forum-specific palette/avatar images are not hardcoded. No physical mobile device
verification was performed.
