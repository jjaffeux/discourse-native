# Phone container and header surface parity

Reference: `discourse-native-mockups` at `7c86328`, the running phone layout,
and the supplied October 14 screenshots (Native iPhone first, mockup second).

The mockup's phone root has `background: none` inline, but its global
`[data-glass] [data-panel]` stylesheet overrides that declaration with
`!important`. Native had copied the inline intent and omitted the resulting
paint. Its root list therefore exposed the gradient behind all the text and
lost the visible separation from the window header.

`ForumMobileSurface` now paints one Native `DPageSurface` for root screens as
well as pushed pages. All destinations use square corners, including pushed
readers. Inner pages continue to inherit a clear surface so the panel fill
paints once. The window header stays on the canvas.
Existing palette tint, material selection, opacity and accessibility settings
remain the source of its fill.

The shared panel painter also matches the CSS edge treatment: a constant
1px white inset rim (14% dark, 75% light), the existing 140px top gradient,
and the soft `inset 0 1px 1px` top highlight. The rim no longer fades toward
the panel bottom. This correction also applies to existing desktop panels.

Focused validation:

- `test/forum_mobile_surface_test.dart`: rendered root/reader, light/dark,
  both materials, opacity endpoints and high-contrast fallbacks; verifies
  header ground, reading fill, both square top corners.
- `test/material_surface_test.dart`: rendered panel edges and highlights.
- `test/mobile_shell_test.dart`: production phone composition, navigation,
  scroll/header/dock behavior and text scaling. Its two existing
  "minimized composer and dock consume the bottom safe area once" variants
  fail on unchanged main too because they look for the retired Minimize text.
- Targeted static analysis of changed implementation, fixture and tests.

`lib/mobile_panel_review_main.dart` is an account-free native capture fixture
using the production surface owner and existing Native controls:

```sh
flutter run -d <simulator-id> -t lib/mobile_panel_review_main.dart \
  --dart-define=MOBILE_PANEL_CAPTURE=true
```

It saves 16 captures in the platform temporary directory, covering light/dark,
Standard/Liquid Glass, opaque/translucent and root/reader. These provide native
panel/header rendering evidence; sample discussion text is not a whole-app
content or typography comparison.

The October 14 reader correction removes the route-dependent corner exception.
Root, reader, sidebar, chat and other destinations all inherit the same mobile
frame. Topic and message readers also no longer overlay a fixed separator at
the header edge; post separators stay in the scrolling content, matching the
list treatment and avoiding a dark line as the header retracts.
