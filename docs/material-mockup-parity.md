# Flat appearance

The app uses one flat appearance on every platform. Fonts, icon sets, forum
palettes, opacity, and background textures remain configurable.

Native components own control fills, borders, interaction states, focus rings,
validation rings, semantics, and visible hit bounds. Pages, menus, dialogs,
sheets, cards, tabs, and the mobile dock use flat fills without depth painters,
raised shadows, inset highlights, or backdrop lenses.

Appearance JSON versions 1, 2, and 3 remain readable. Legacy `material` values
are ignored. Saving appearance preferences omits that key and preserves the
other settings.

The native glass bridges, shader renderer dependency, backdrop capture helpers,
and OS Reduce Transparency channel are removed. Reduced-motion preferences
still govern transitions and animated background textures.

Focused behavior coverage lives in `test/appearance_preferences_test.dart`,
`test/app_settings_page_test.dart`, `test/flat_surface_test.dart`,
`test/surface_compositing_test.dart`, and `test/stream_day_separator_test.dart`.
These suites cover preference migration, palette fills, sheet opacity, rounded
corners, exact control targets, menu behavior, transition state, and date actions.
