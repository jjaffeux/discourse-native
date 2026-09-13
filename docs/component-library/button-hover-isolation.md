# Button hover isolation — 2026-09-11

Moving between adjacent DButtons left the outgoing hover fill visible during
its 150ms fade. A rendered-decoration regression measured alpha 0.894 on the
previous ghost button 16ms after moving to its neighbor. Resolved state alone
was already correct, so tests that waited for animations missed the overlap.

DButton now clears its surface transition immediately on hover exit. Other
state transitions retain their existing duration. No public API or layout
changes are needed. Regression coverage checks rendered fills for separate
vertical icon buttons and joined horizontal groups in light and dark themes.

Verification:

- Button, button-group, reference, styleguide and user-menu accessibility suites:
  60 tests passed before expanding the hover regression to four combinations;
  all four expanded combinations passed.
- Integrated button, button-group and topic-inbox suites: 108 passed, one
  existing failure. The reader-footer test expects Reply and Bookmark to touch,
  but production intentionally separates their nested groups by 8px. The same
  test failed after restoring the unmodified main DButton source.
- `flutter analyze --no-pub`: clean on the integrated candidate.
- macOS debug build of `tool/button_custom_colors_review_main.dart`: passed.
  Native fixture inspected in dark and light palettes, at 640px and 320px
  content widths, including the joined category browse hover/tooltip. The
  running main app's palette/settings rail was also inspected before the fix;
  its settled hover was isolated. Sub-frame overlap and its removal are verified
  by rendered widget tests, not the native screenshots.

## Hover entry correction — 2026-09-13

The notification bell and Personal inbox trigger both use DButton. The previous
exit-only fix left a 150ms entry transition, painting intermediate backgrounds
before reaching the intended hover fill. Hover entry now snaps to the resolved
surface as well. Focus and press transitions retain their shared motion.

A regression inspects actual DecoratedBox fills at entry and subsequent frames,
then leaves and re-enters each variant in light and dark palettes. Before the
fix, 26 of 30 combinations failed; link variants with unchanged fills passed.
After the fix, all 112 focused button, reference, button-group, inbox-menu,
header-notification, user-menu accessibility and button-styleguide tests pass.
The reference test also verifies that keyboard focus still animates its ring.

`flutter analyze --no-pub` and the macOS debug build of
`tool/button_custom_colors_review_main.dart` pass with Flutter 3.47.2.
The isolated native custom-color styleguide fixture launched and was inspected
in dark at 640px and light at 320px, including joined category controls. Native
screenshots establish settled appearance; sub-frame hover timing is verified
by widget tests, not native screenshots. No visual baselines or public APIs changed.
