# Typography

`lib/src/theme/discourse_typography.dart` owns every base font size and the
semantic Material text theme. AppTheme applies it to light, dark, site palette,
and Cupertino themes. Widgets choose a role and override color or emphasis
when needed; they do not invent another size or line height.

## Scale and roles

The scale uses [Tailwind's size/leading pairs](https://tailwindcss.com/docs/font-size).
Its smaller steps suit a dense interface; larger steps establish heading
hierarchy. This is an established stepped scale, not a constant-ratio scale.
[shadcn's buttons](https://github.com/shadcn-ui/ui/blob/main/apps/v4/registry/new-york-v4/ui/button.tsx),
[sidebar](https://github.com/shadcn-ui/ui/blob/main/apps/v4/registry/new-york-v4/ui/sidebar.tsx),
and [tables](https://github.com/shadcn-ui/ui/blob/main/apps/v4/registry/new-york-v4/ui/table.tsx)
share compact interface sizing. [Radix](https://www.radix-ui.com/themes/docs/theme/typography)
also treats size and leading as paired tokens. We adapt those principles to
Flutter while keeping the platform font family and Discourse colors.

| Purpose | TextTheme role | Size / line height at 100% |
| --- | --- | --- |
| Captions, dates, counts, secondary metadata | bodySmall, labelSmall | 12 / 16 |
| Sidebar destinations, menu items, form inputs, table cells, previews | bodyMedium | 14 / 20 |
| Buttons, navigation tabs, table headings | labelLarge | 14 / 20, medium weight |
| Secondary interface labels | labelMedium | 14 / 20 |
| Posts, chat, composer, reading content | bodyLarge | 16 / 24 |
| Topic, user, group, and card row titles | titleSmall | 16 / 24, medium weight |
| Section headings | titleMedium | 18 / 28, semibold |
| Dialog and sheet titles | titleLarge | 20 / 28, semibold |
| Page titles | headlineSmall | 24 / 32, semibold |
| Larger headings | headlineMedium | 30 / 36, semibold |
| Display headings | headlineLarge | 36 / 40, semibold |

Small and large buttons change spacing and icon geometry while keeping the
same label role. Narrow layouts keep the same type roles and provide larger
touch targets. Authored h1–h6 use 30, 24, 20, 18, 16, and 14 with their paired
leading in both cooked HTML and the composer. Relative authored formatting
(small, big, superscripts, inline code) derives from its surrounding text;
zero-size syntax spans in projected editors are deliberately invisible.

## Zoom

All theme sizes remain unscaled. `AppTextScaleRegion` at the MaterialApp builder
composes the platform TextScaler with the app's 80–200% preference. This also
covers Navigator overlays, dialogs, tooltips, and menus. Custom text measurement
uses `MediaQuery.textScalerOf(context)` so layout follows the rendered text.
Do not multiply a TextStyle's fontSize by zoom or replace the inherited scaler.

Tabs and sidebar rows grow with text. Dropdown rows size intrinsically. Table
rows must admit taller cells, and constrained navigation can scroll. Long row
labels may ellipsize, but text must not be squeezed into a shorter fixed box.
Decorative forum initials fit their avatar bounds; their adjacent forum labels
continue to scale normally.
The HTML package currently consumes a linear compatibility factor anchored to
16-point reading text; it applies that factor internally, so its rendered
fontSize already includes zoom.

`typography_boundary_test.dart` verifies rendered control roles at every zoom,
light/dark themes, overlay inheritance, and nonlinear platform scaling.
`sidebar_width_test.dart` covers narrow and wide sidebar reflow at 200%.
The source adoption test guards the single owner of numeric font sizes.
