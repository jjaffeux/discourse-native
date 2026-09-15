# Sidebar spacing study

Three compositions of the existing Native Sidebar, inspired by the supplied
Discord screenshot. At the start of this study, the application used 32px large
sidebar buttons and a 1px gap in `lib/src/shell/instance_sidebar.dart`.

| Option | Row height | Gap after each row | Label-to-label distance |
| --- | --- | --- | --- |
| Current | 32px | 1px | 33px |
| Comfortable | 32px | 6px | 38px |
| Relaxed | 32px | 10px | 42px |

**Selected: Comfortable.** The application now uses a 6px gap after top-level
destinations and section headers. Existing row heights, text scaling and the
Native submenu's 4px spacing remain intact. Lazy row extents include the gap.

Each preview has the same 272px
width, 724px height, content, font, icon sizes, selection, and section geometry.
The Relaxed version requires scrolling to reach the last direct message. The
Current column reproduces the current row sizing, not an exact production
screen: the sections and names are local sample data.

## Preview

- [Dark comparison](dark.png)
- [Light comparison](light.png)

The PNG files are static renders. Launch the interactive Flutter mockup from
the repository root:

```sh
flutter run -d macos -t tool/sidebar_spacing_mockup.dart
```

Select Compare or an individual density, switch Light/Dark, hover and select
rows, and scroll each sidebar independently. Selection is synchronized across
all three columns. The sample has no network or account persistence.

## Native composition

All components import `package:discourse_native/discourse_ui.dart`: DSidebar,
DSidebarContent, DSidebarHeader, DSidebarGroup, DSidebarGroupLabel,
DSidebarMenu, DSidebarMenuItem, DSidebarMenuButton, DSidebarMenuBadge, DAvatar,
DIcon, DToggleGroup, DCard, DText, DSeparator and DScrollArea.

Only ordinary layout padding between rows varies. The existing large control
preset owns the 32px row, text, hover, selection, focus and hit behavior. This
mockup does not introduce a new size preset or modify shared kit components.
The larger group-to-group distances in the roomier columns accumulate
from the additional row gaps; section padding itself stays fixed.

## Verification

- `dart analyze tool/sidebar_spacing_mockup.dart tool/render_sidebar_spacing_mockup_test.dart`
- `flutter test tool/render_sidebar_spacing_mockup_test.dart`
- `git diff --check`

Both palettes were rendered and visually inspected at 1000×1120 logical pixels.
The renderer uses real Native widgets, the Flutter widget-test engine, 1× pixel
ratio, and `/System/Library/Fonts/SFNS.ttf`. These are widget-test renders, not
native macOS screenshots. The focused renderer also exercised row selection,
single-option mode and a 390px layout without framework errors. A native app
launch was not performed. Export again with the Flutter test command above.

## Application adoption — 2026-09-15

The approved 6px gap is applied through the existing `_sidebarRowGap` in
`InstanceSidebar`. Both the padded lazy child and its fixed extent use that
value, so scrolling keeps its 32px desktop / 48px touch controls. Section
headers use the same gap; scaled rows still grow from their contents. Updated
the existing hover, separator, custom-section and scaled-header expectations.

Verification:

- All 270 existing tests across shell navigation, sidebar width, chat shell,
  category sidebar and tag sidebar passed.
- Full root `dart analyze --fatal-infos`, formatting and `git diff --check`
  passed.
- Built `tool/sidebar_review_main.dart` and launched an isolated, ad hoc signed
  macOS bundle. Inspected the real production sidebar at 208px width in light
  and dark, dark at 200% text, custom-link scrolling, and the chat list through
  Channel 99 and its final direct message. Hover separation was also visible
  on the chat rows. The normal application build and account were not used.
- No physical iOS or Linux checks were performed. The native review app was
  quit after inspection.
