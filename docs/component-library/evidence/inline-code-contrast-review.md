# Inline code contrast — 2026-09-19

Requested: distinguish inline code across color schemes, including code inside
neutral conversation bubbles with surrounding monospace text.

Native typography now owns the treatment: 12% foreground/background fill, 24%
outline, 1px inside border and existing 4px corners. `DText.code` preserves the
compact authored-content padding (4px horizontal, 1px vertical). Posts and chat
use it through the shared `InlineCode` adapter. Composer and selectable text
spans use the same fill without changing their native text representation.
Fenced code, syntax colors, authored whitespace and link colors are preserved.

14% fill was evaluated first, but reduced Rose's foreground contrast to 4.40:1.
12% passes the 4.5:1 text threshold for all ten presets in both light and dark
modes, improves fill separation from the neutral bubble, and keeps the outline
above 1.2:1 against that bubble. The outline threshold is a visual regression
target, not a claim about control accessibility. Arbitrary custom palettes can
still have poor base foreground/background contrast.

Verification on the integrated candidate (implementation `87b6ed43`, main base
`ce34cfc0`):

- `dart analyze`: no issues.
- `flutter test --no-pub` for inline_code_contrast, ui/d_typography, cooked_html,
  markdown_style, post_text_selection, chat_preview, styleguide/styleguide_page,
  and forum_theme tests: 225 passed.
- `flutter build macos --debug --no-pub -t tool/inline_code_review_main.dart`:
  successful using the repository's Flutter 3.47.4 pin.
- Native macOS inspection of the real new typography example and CookedHtml
  inside DBubbleContent: light, dark, forest and plum palettes, page and bubble
  surfaces, monospace prose, wrapped code, and linked code. Inspected the
  two-column window and resized it to a single-column layout. No clipping or
  visible border-induced spacing change.
- The isolated `/tmp/InlineCodeReview-4a78.app` launched successfully after
  ad-hoc signing without push, team, or application-identity entitlements;
  sandbox and JIT entitlements retained and read back. Quit it after inspection.
- Widget tests cover compact spacing, palette changes, link foreground,
  whitespace, text scaling, narrow layout and selection behavior. No native
  iOS or Linux device run was performed.
