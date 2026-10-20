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

`liquid_glass_easy` 5.0.0 supplies **rendering only** (`LiquidGlassLens`,
`LiquidGlassLite`, `LiquidGlassBatch`). Package buttons, switches, scaffolds,
menus and dialogs are not used. SDK validation used Flutter 3.47.6 / Dart 3.13.5.
See the [package documentation](https://pub.dev/packages/liquid_glass_easy).

Raised glass controls and selected dock buttons keep the package's original
specular band and add a 5px glow at 129 degrees to fill the corner gaps, with
intensity 1 and spread 0.85. This shared button preset preserves the default
refraction, blur, color, saturation, shadow, and adaptivity. The kit does not
paint an additional 1px highlight over those lenses. Standard surfaces and
recessed wells retain their existing edge treatment. Menus, dialogs, sheets,
and dock capsules keep their existing glass presets; menus retain their
separate top sheen.

Live lenses must stay outside fractional-opacity layers. Glass dialogs, pickers,
tab changes and panel folds keep their movement without fading the live surface.
Captured page images can still crossfade. Covered topic chrome hides immediately
in glass appearance. Disabled raised controls dim their flat artwork and tint
independently of the lens, preserving the disabled state and visible hit bounds.
Already-loaded shaders are reused on the first frame of each new surface.
`test/glass_compositing_test.dart` covers these production paths in both materials
and brightness modes; its integration wrapper checks the native shader renderer.

- **iOS/Impeller:** lenses refract the app's live backdrop. The iPhone 18 Pro
  simulator on iOS 27 reported Impeller/Metal, shader filters supported, and
  successful shader initialization. Both brightness modes and 200% text were
  captured. This is simulator evidence, not physical-device validation.
  Rounded reading panels use saved clipping so scrolling content stays inside
  their border. Controls inside those panels use the package's frosted renderer,
  preserving live blur, tint and rim without shader edge refraction. Nested page
  sheets clip their own border too. Header and dock controls, floating menus,
  dialogs and ordinary sheets retain the native lens path.
- **macOS/Skia:** this Mac reported Skia/Metal and no shader image filters.
  Controls therefore use live frosted blur, tint and a surface-colored rim;
  they do **not** claim in-app refraction. No duplicate background capture is
  created. A shader failure also keeps a readable frosted path.
- **macOS native window:** on macOS 26+, the host installs a full-window passive
  `NSGlassEffectView`; older macOS uses under-window `NSVisualEffectView`
  vibrancy. AppKit owns this separate backdrop below Flutter's input view.
  Flutter lenses do not sample other desktop windows. macOS 26.6 was built and
  inspected natively; an older-macOS device was unavailable. Compatibility
  wrapper host sources were syntax checked, not separately packaged.

## Validation

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
