# Shared input sizing

Text inputs and file inputs now accept `DControlSize`, defaulting to regular,
with the same 24/28/32px small/regular/large surfaces as buttons, selects and
menu triggers. Input groups pass their size to the editor and inline addons.
The shared text-scaling rule grows surfaces at enlarged text sizes; mobile
controls retain their 48px accessible targets. Labels and help/error text sit
outside the field surface. Borderless editors retain custom typography.

The Input styleguide includes a Shared sizes example beside matching buttons.
The cross-control regression checks text/file inputs and input groups with a
text addon alongside the existing controls at 100% and 200% text scaling.

Verification on 2026-09-17:
- 70 focused widget tests passed across shared sizing, input, input rendering,
  input groups, borderless groups, button groups and Input styleguide examples.
- 28 existing topic-header/tag/assignment tests passed in the independent
  header audit. Category dropdowns, browse buttons and Add tag already paint
  24px small surfaces; Assign topic also uses the same small preset.
- `flutter analyze --no-pub` passed.
- Native macOS local-data input fixture inspected in light at 100% and dark
  at 200%, including the production Add a Site form's field and Connect button.
  No account submissions were made. Native mobile testing was not performed.
- Installed Flutter was 3.47.4; the repository's SDK pin was not changed.
