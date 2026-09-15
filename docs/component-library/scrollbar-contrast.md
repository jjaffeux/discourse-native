# Scrollbar contrast and spacing

Updated 2026-09-15.

`DScrollBar` and `DScrollArea` choose a subdued thumb with at least 3:1
contrast against the theme background. Pass `backgroundColor` when the painted
container uses another surface; this does not paint a background itself.
Code blocks, Select, Command and dropdown menus supply their own surface.
Explicit `DScrollThumb.color` overrides remain supported.

The kit and application scrollbar theme share a 1 logical pixel inset on both
axes and retain the existing 4px thumb width. Theme changes recompute the color
without replacing the scroll position. Hidden scrollbars remain hidden.

Verification:

- Flutter 3.47.2; full `flutter analyze --no-pub`: no issues.
- 161 focused widget tests passed across Scroll Area, its styleguide, code
  blocks, Select, Command, dropdown menus and app themes.
- Pixel assertions cover the clear container edge in LTR/RTL and both axes;
  contrast checks cover white, black, middle gray and a colored dark surface.
- The macOS standalone styleguide was built and inspected at its default
  desktop window size: content/panel/popup surfaces in light and dark palettes,
  live theme changes after thumb dragging, horizontal artwork and the RTL list.
- Native application code-block and popup flows were not separately exercised;
  their coverage here is through the focused widget tests.

This deliberately increases the original reference's faint border-token thumb
contrast in response to the requested visibility improvement.

Follow-up: automatic Material scrollbars also have a pixel regression test at
2x rendering scale, in light/dark themes and LTR/RTL while hovered. Their outer
edge stays clear and their thumb remains visible. All 13 Scroll Area tests pass.
