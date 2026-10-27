# Appearance

The app uses one solid appearance on every platform. Fonts, icon sets, forum
palettes, opacity, and background textures remain configurable.

Desktop reading panels keep their opaque palette fill so the darker window
canvas does not darken them. Panel opacity remains configurable on phones.

Native components own control fills, borders, interaction states, focus rings,
validation rings, semantics, and visible hit bounds. Controls, tabs, and the
mobile dock use flat fills. Pages, panels, sheets, menus, popovers, dialogs and
directory cards stand off the window's ground as the mockup's look A draws
them. They take a 1px inset rim, a 1px catch of light along the top and
painted drop shadows. [Surface depth parity](surface-depth-mockup-parity.md)
maps each one to its mockup selector. There are still no glass tints, backdrop
lenses, or blur layers.

Appearance JSON versions 1, 2, and 3 remain readable. Legacy `material` values
are ignored. Saving appearance preferences omits that key and preserves the
other settings.

The native glass bridges, shader renderer dependency, backdrop capture helpers,
and OS Reduce Transparency channel are removed. Reduced-motion preferences
still govern transitions and animated background textures.

Focused behavior coverage lives in `test/appearance_preferences_test.dart`,
`test/app_settings_page_test.dart`, `test/flat_surface_test.dart`,
`test/surface_depth_test.dart`, `test/surface_compositing_test.dart`, and
`test/stream_day_separator_test.dart`. These suites cover preference
migration, palette fills, surface edges and shadows, sheet opacity, rounded
corners, exact control targets, menu behavior, transition state, and date
actions.
