# Appearance material parity

Reference: native-mockups snapshot `54ba01c`, with material/depth changes from
`704e8b9`, `012ecab`, and `88bb68c`. Existing account, font, palette and inline
control contracts remain in use.

## Implemented behavior

- macOS and iOS always select **Liquid glass**, including installations with
  an existing Standard preference. Forums, app settings and styleguide palette
  previews use the same platform policy; Apple settings omit the style selector.
  Other platforms retain the Standard/Liquid glass choice and its saved value.
  The appearance store stays compatible with JSON versions 1, 2 and 3.
- Both styles use raised controls, recessed choice/input wells, selected
  surfaces, lit edges and layered panel/menu shadows. Reading cards and palette
  swatches keep solid colors. Primary/destructive actions keep their existing
  palette and foreground colors. Selected forum icons use a passive Native card.
- Glass adds palette-colored ground pools, translucent panels and controls,
  and a deeper menu frost. A docked sidebar shares the window ground; an overlay
  sidebar uses its existing Native sheet. Native controls retain their sizes,
  hit testing, focus/validation rings, disabled behavior and semantics.
- Light and frost paint behind content. Changing material retains the editor
  element, unsaved text and focus. Compact cards/choice groups batch their
  Impeller controls. Page panels and overlapping popovers take independent
  backdrop reads, so fixed controls sample the surfaces painted beneath them
  as the reader scrolls.
- Opacity preserves the existing normalized stored preference. At its least
  opaque end, Standard panels are 70% opaque and the ground 62%; glass panels
  are 60% opaque and the ground 35%. The glass readout follows ground opacity,
  matching the reference's 65% ground and 40% panel transparency ceilings.
- Texture choices are None, Paper, Hatch and Lava lamp. Hatch paints behind the
  content, never over glyphs. Previously saved gradients still parse and render.
  Existing palette tint and texture intensity remain independent of material.
- OS Reduce Transparency updates live through the native host and restores
  opaque surfaces without replacing the saved style. High contrast does the
  same. Existing reduced-motion texture behavior remains; lenses add no touch
  animation, control or gesture owner.

## Rendering paths

`liquid_glass_renderer` 1.0.0-dev.1 supplies rendering through
`LiquidGlass`, `LiquidGlassLayer`, and `LiquidGlassCapture`. Native components
continue to own controls, geometry, focus, semantics, and hit areas. The package
is pinned because its 1.0 prerelease replaces the 0.2 API. It requires Flutter
3.47 or newer. See the [package README](https://pub.dev/packages/liquid_glass_renderer).

Controls and the dock use the package's regular iOS 27 settings and appearance
for the app's selected brightness. Explicit tints use the direct color model.
Floating dates, menus, dialogs, and sheets keep 16px frost and their supplied
tints. Reading panels, recessed wells, cards, and swatches retain painted fills.
Dock typography and dimensions belong to Native and retain their previous values.
The reversible dock spring uses Flutter physics with stiffness 195 and damping 19.5.

Each glass surface keeps its original paint position. `DMaterialBatch` supplies
one stable backdrop key to sibling layers, saving copies without moving selected
glass behind a recessed well. Menus, dialogs, and sheets reset the inherited key
so they can sample intervening painted content. Overlapping dock glass uses a
small `LiquidGlassCapture` rather than a shared key, preserving glass on glass.
Controls inside reading panels give their own glass a small capture as well.
Native pixel checks found that omitting these captures lost the glass in the
full settings composition. The captures cover individual controls, rather than
whole reading panels. Each captured pass uses an independent key. Nested batches
preserve this policy; overlays reset it and the dock owns its existing capture.
No blend groups or extra glass shadows are introduced.

The [performance guidance](https://pub.dev/packages/liquid_glass_renderer#performance)
identifies backdrop copies as the primary cost. Glass bounds stay local to each
control. Independent cards and overlays can still require separate copies.
`FakeGlass` is an automatic compatibility fallback and still pays for copying
and blur. High contrast and Reduce Transparency keep the existing opaque path,
which avoids those costs. No physical-device speedup is established by this swap.

Live glass stays outside fractional-opacity layers. Disabled controls dim their
artwork independently of the glass. Native dock visibility gates continue to own
hit testing and semantics. Resources load on first use in the application, using
the renderer's temporary fallback. Native test fixtures explicitly precache them.

Both macOS and iOS enable Flutter GPU. macOS also explicitly enables Impeller,
replacing the previous Skia workaround. The compatibility application in
`profiles/full` carries the same flags. Unsupported engines use automatic
`FakeGlass`. Native macOS captures cover light, dark, and 200% text states. Native macOS and
iOS simulator pixel checks verify GPU glass and saved clips. These are rendering
checks, not physical-device performance evidence. The panel clip integration
test verifies visible controls and saved rounded clips on iOS.

The macOS host's passive `NSGlassEffectView` on macOS 26 and newer, or
`NSVisualEffectView` on older systems, remains separate from Flutter glass.
Flutter glass samples application content rather than other desktop windows.

## Previous material validation

This section records the earlier material migration before the renderer swap.

Focused regressions cover persistence/migration, live accessibility overrides,
visible control bounds and gaps, disabled actions, retained editing state,
mouse menu opening, opacity ceilings, hatch placement and rendered frost.
Directly related Native control, app settings, theme/editor, rail semantics,
texture and full app-theme tests passed. Targeted analysis and diff checks pass.
Native macOS profile and iOS simulator builds loaded the package shaders.

Integration rebased onto `074a80aa5`, with the other six mockup groups present.
Supplementary composer controls, docking, close-safety and drafts checks yielded
122 passes and 87 failures; the exact same 87 tests failed on unchanged main.
Representative baseline failures find an older reply tooltip or expect 16px
footer spacing where main now renders 14px. The material branch introduced no
additional failures in that comparison. The combined macOS host source also
passed Swift syntax checking.
The touched app-theme test was aligned with the merged sidebar design: forum
identity and its switcher precede the mode tabs. Its former no-header assertion
failed identically on unchanged main before that test update.

`lib/material_review_main.dart` is a reproducible component fixture with 24
cards, 48 row buttons, primary/outline/disabled/destructive controls, an input,
choice wells and a frosted reading surface. `MATERIAL_REVIEW_CAPTURE=true`
saves light/dark, desktop/narrow-200%-text images to the platform temporary
folder and logs engine capabilities plus three scrolling round trips per mode.
The fixture contains no forum/account data and makes no API requests.

```sh
flutter run -d macos --profile -t lib/material_review_main.dart \
  --dart-define=MATERIAL_REVIEW_CAPTURE=true
flutter run -d <simulator-id> -t lib/material_review_main.dart \
  --dart-define=MATERIAL_REVIEW_CAPTURE=true
```

The local macOS profile required an unsigned build and local ad-hoc signing
because its development provisioning profile was unavailable. Repository
signing settings were preserved. Native frame measurements and limitations
are recorded with the review captures; they do not establish whole-app FPS or
physical iOS performance.
