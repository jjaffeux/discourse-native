# Per-button custom colors

The user requested category-tinted backgrounds and borders for the split
category controls on 2026-09-10. This is an authorized extension of the existing
Button owner, rather than an additional catalogue component.

Both `DButton` and `DButton.iconOnly` accept nullable `backgroundColor` and
`borderColor`. Omitted values keep the existing variant styling. Supplied
colors retain their alpha and update on rebuild; passing null restores the
current theme's variant.

- `backgroundColor` replaces the fill in every state, including expanded,
  disabled and loading. Foreground/icon colors remain variant-owned.
- The existing `interactiveBackgroundColor` overrides that fill on hover/focus
  and compatibility-variant presses. Existing expanded-state precedence is
  unchanged: an expanded secondary button keeps its expanded fill.
- `borderColor` replaces the one-pixel frame, including while focused. The
  theme's exterior focus ring remains visible. Invalid styling takes precedence
  over the supplied border color.
- `DButtonGroup` keeps ownership of joined corners and omitted shared edges;
  tinting requires no group API or rendering changes.

The Button styleguide's **Custom colors** example composes two category pickers
from `DCombobox`, `DButtonGroup` and `DButton`. It uses a 10% category fill,
25% category border, and an explicit category hover blend. Selecting a different
local category updates both halves; browse actions report independently.
The example also includes a disabled tinted button.

`tool/button_custom_colors_review_main.dart` mounts that actual example with
light/dark/custom palettes, width, text-scale and direction controls. It uses
local sample data and does not access accounts. Production category/tag pickers
remain the existing app adapters; this follow-up adds the requested kit capacity.

## Verification

- Locked dependency resolution passed without modifying any lockfiles or SDK
  pins. Formatting and root `flutter analyze --no-pub` passed.
- Focused Button, Button reference, Button Group, their styleguide examples,
  Combobox and Button adoption tests passed with seed `9102026`. New coverage
  checks translucent fills/borders on both constructors, hover/press/expanded
  state precedence, focus/invalid state, live updates and clearing overrides,
  disabled/loading guards, independent picker/browse actions, and rendered
  pixels across a translucent joined border.
- The adoption check exposed an obsolete exception for two raw Material
  controls in `composer_panel.dart`; those controls already use `DButton`.
  The stale exception was removed and the guard passed.
- The real Custom colors example passed the existing 260px, 200% text, RTL
  matrix in light, dark, Forest and Plum palettes.
- Built `tool/button_custom_colors_review_main.dart` with
  `flutter build macos --debug --no-pub --target
  tool/button_custom_colors_review_main.dart`. The copied review bundle uses
  `org.discourse.native.button-custom-colors-review`, with restricted app/team/
  push entitlements omitted. Deep/strict signature verification and the actual
  native launch passed; the real application's signing configuration was not
  changed.
- On macOS, inspected the tinted split controls in dark and light palettes,
  a 320px viewport at 200% text, and the Plum palette with RTL. Exercised the
  browse action, opened the picker, typed `support`, selected it with Down and
  Return, and observed both halves change tint while the focus ring remained
  visible. Native accessibility exposed independent Edit buttons and Browse
  links. The review app was quit and its process disappearance was verified;
  the desktop lease was released.
- The native review kernel SHA-256 was
  `afa84d5f07db23cfab1e8bdadc0e371d3300e90a02326f575cf356ac2c4ae06d`.
  Subsequent example edits were Dart formatting only. Native screenshots are
  recorded in the implementation task. No iOS/Linux device or spoken screen
  reader session was run.

Logs: `/tmp/button-custom-colors-final-tests.log` (104 passing checks and the
then-stale adoption exception), `/tmp/button-custom-colors-final-guard.log`
(14 passing Button Group/adoption checks after correction),
`/tmp/button-custom-colors-final-analysis.log`, and
`/tmp/button-custom-colors-build.log`.
