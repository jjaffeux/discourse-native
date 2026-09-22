# macOS panel corners

The desktop panel touching the window's bottom-right corner now uses concentric
rounding: the native window radius minus the workspace's 6-point inset. The
titlebar-only window reports 16 points on macOS 26 and 10 on earlier versions;
native fullscreen reports zero. Both macOS application wrappers expose the same
window-channel method. These are the host's window-style metrics, not private
AppKit introspection.

The shell passes the corner through the topic-list/reader split and composer
dock. Swapping panels, docking left/right/bottom, minimizing, restoring and
closing the composer transfer ownership. Docked diagnostics remove the corner
from the workspace; their flush outer edge is clipped by the native window.
In RTL the rail occupies the physical right edge, so workspace panels retain
their theme radius. Other platforms and nested appearance previews retain their
existing corners.

Native `DCard.borderRadius` owns both the border and content clip;
`DPageSurface.borderRadius` forwards it when framed. All other corners retain
the theme's Card radius. The Card styleguide includes a Window corner example.

## Verification — 2026-09-22

- Static analysis passed.
- Focused Card, Page Surface, shell, composer-docking and topic-inbox tests
  cover directional corners, native radius/size changes, disabled edge
  ownership, Windows, nested cards, panel swapping and composer transitions.
- Existing mobile shell, styleguide, appearance-preview/background and control
  adoption tests passed.
- A macOS debug build succeeded. An isolated, ad-hoc-signed local-data fixture
  mounted the production AdaptiveShell and Card Window corner example. Native
  inspection on macOS 26.6.2 covered light/dark palettes, swapped topic panels,
  a right/bottom/fullscreen/minimized composer, and a 650-point-wide fixture.
  Rounded borders and footer clips were visually checked against the actual
  window's corner. No account data was used.
- Legacy macOS and native OS fullscreen radius handling were checked through
  mocked host responses; those OS configurations were not run on a device.

The integration candidate preserves the fullscreen composer frame and composer
block insertion changes already merged into main.
