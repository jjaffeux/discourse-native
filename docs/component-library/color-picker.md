# Color picker

`DColorPicker` is a user-requested Native kit addition, exported by
`discourse_ui.dart` and listed in the application styleguide catalogue. It
accepts a controlled opaque `Color`, nullable `onChanged`, and semantic label.
The existing Button and Popover own the trigger, focus, placement and dismissal;
Slider owns keyboard and accessible HSV adjustment. A draggable color plane
provides direct saturation/value selection. Alpha is intentionally unsupported
because forum palettes use six-digit RGB colors.

All seven custom theme fields use the picker as their prefix action. Hex typing
remains available. Invalid partial hex values retain the corresponding role's
last valid picker color. Changes update the local draft and preview; Save theme
still controls persistence. Import, starting palettes and Surprise me continue
to update the same controllers.

Independent review caught and verified fixes for hues above 359 degrees,
parent-rejected controlled values, and invalid-hex fallback. Thirteen focused
widget/adoption tests pass, including near-red, accepted/rejected updates,
keyboard adjustment, Escape, disabled state, and a picker-to-hex/preview flow
at 390px. Static analysis of changed Dart files is clean. The macOS debug fixture
build passed; the isolated review bundle was inspected in light/dark modes,
including opening different swatches, dragging the plane, hue adjustment,
live hex and preview updates, and outside-click dismissal. Escape was verified
in widget tests; native automated Escape did not produce a visible change.
The isolated review application was quit after inspection.
