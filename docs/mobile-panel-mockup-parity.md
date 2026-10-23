# Phone container and header surface parity

Reference: `discourse-native-mockups` at `a4c4875`, the running phone layout,
and the supplied October 20 screenshot of the Start page.

The mockup's phone root has `background: none` inline, but its global
`[data-glass] [data-panel]` stylesheet overrides that declaration with
`!important`. Native had copied the inline intent and omitted the resulting
paint. Its root list therefore exposed the gradient behind all the text and
lost the visible separation from the window header.

`ForumMobileSurface` now paints one Native `DPageSurface` for root screens as
well as pushed pages. Start, topic lists, ordinary destinations, plugin roots,
and readers share 22px corners on all four sides, the mockup's `pushedCard`
radius at `5e4e72a` ("as round as a sheet"). The October 20 dock-matched
bottom corners were rounder than the reference and are gone. The body starts 6px below the window header and stops above the live bottom
safe-area inset. Inner pages inherit a clear surface so the panel fill paints
once. The window header stays on the canvas.

`MobileForumRoot` consumes the bottom safe area once around the page and floating
dock together. Navigation keeps its ordinary 6px margins. The measured footer
obstruction excludes that consumed safe area, so chat composers clear the dock
without adding another inset. Keyboard resizing uses the live safe padding.
Existing palette tint, material selection, opacity and accessibility settings
remain the source of its fill.

The shared panel painter also matches the CSS edge treatment: a constant
1px white inset rim (14% dark, 75% light), the existing 140px top gradient,
and the soft `inset 0 1px 1px` top highlight. The rim no longer fades toward
the panel bottom. This correction also applies to existing desktop panels.

Focused validation:

- `test/forum_mobile_surface_test.dart`: rendered root/reader, light/dark,
  both materials, opacity endpoints and high-contrast fallbacks; verifies
  header ground, reading fill, and rounded corners.
- `test/material_surface_test.dart`: rendered panel edges and highlights.
- `test/mobile_shell_test.dart`: production phone composition, navigation,
  scroll/header/dock behavior, text scaling, safe-area consumption, and the
  minimized composer's 14px dock clearance.
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
Root, reader, chat and other content destinations inherit the same mobile
frame and its 22px corners. The inset navigation sidebar uses
`ForumMobileSurface.sidebar` with the Native 14px panel radius, matching
`NavSidebarContent`'s `.side-nav.glass-sheet` in the reference. Its fill, inset
rim and top highlight use the shared panel treatment in both materials; the
inner sidebar remains transparent so they paint once. Rendered tests check
rounded corners, palette fill, rim and highlight across light/dark, both
materials, opacity and high contrast.
Topic and message readers also no longer overlay a fixed separator at
the header edge; post separators stay in the scrolling content, matching the
list treatment and avoiding a dark line as the header retracts.
