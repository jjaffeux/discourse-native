# Selector and field redesign — 2026-09-19

The users directory already composed DSelect (period), DCombobox with
DInputGroup (group), DDataTableFilterField with DInput (search), and
DDataTableColumnToggle with DDropdownMenu (columns). No application replacements
were needed. The first three still painted the older Linear field treatment.

Select, Input, Input Group and multi-value Combobox now use the existing
DTokens.buttonTheme outlined surface: 3% foreground fill, 22% border, 8px
corners, 1px outline and no shadow. Select hover/open uses 10% fill and 32%
border. Editing text, focus/error rings, disabled opacity, joined edges,
compact sizing and touch targets keep their existing owners. Custom site
palettes still resolve on every build. This supersedes the field/select
exception in the September 18 button redesign record.

Verification:

- Formatted all touched Dart files. Root analysis has only the pre-existing
  prefer_const_literals_to_create_immutables info in content_route_test.dart:19.
- Select, Combobox, Input, Input Group, borderless Input Group, control sizing,
  control consistency, Linear example and adoption checks passed. Updated Input
  pixel assertions verify the new fills and preserve focus/error-ring and
  disabled-opacity checks; all four pixel tests pass.
- Control comparison golden checks pass for light, dark, Forest and Plum,
  including rest, hover and open. Reviewed representative renders in all four
  palettes (720x480, bundled JetBrains Mono, Flutter widget-test renderer).
- Users-page and selection-consumer checks retain two failures reproduced on
  untouched f0dbac049 in /tmp/selector-style-baseline: the desktop target test
  expects 32px instead of the existing 28px; the older review launcher expects
  a Select in Assigned topics. No new behavior failure remains.
- Built tool/users_table_review.dart as a macOS debug app and launched an
  isolated ad-hoc copy with restricted identity/push entitlements omitted;
  signature verification and entitlement readback passed. Inspected the actual
  UsersPage toolbar in light/dark, opened both selectors, changed Week to Month,
  selected staff, and checked 390px / 200% text / RTL. Inspected the native Data
  Table styleguide's RTL filter, columns and page-size controls. No overflow in
  the changed toolbar. No iOS device or spoken screen-reader testing performed.
- Flutter 3.47.4 / Dart 3.13.3; repository pin and lockfiles unchanged.
