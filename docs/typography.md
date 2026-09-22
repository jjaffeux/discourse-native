# Typography

The application uses **one scale on desktop and mobile**, measured from the
local HTML design reference on 2026-09-23. See [Application design rules](design/reference-rules.md)
for the full page recipes, spacing, radii, palette and source inventory.
This replaces the earlier shadcn size pairs and the 120% mobile baseline.

`DiscourseTypography` owns numeric sizes and the semantic `TextTheme`.
`AppTheme` applies it to light, dark, forum and Cupertino themes. Use a role
and override color or emphasis where necessary. Keep font sizes unscaled.

## Scale and roles

All measurements below are logical pixels at 100% app zoom.

| Purpose | Role / token | Size / line height | Weight |
| --- | --- | --- | --- |
| Tiny taxonomy labels | micro | 11 / 16.5 | By state |
| Bylines | labelSmall | 11.5 / 17.25 | 500 |
| Dates, counts, metadata | bodySmall | 12 / 18 | 400 |
| List excerpt | preview, DItemDescription | 12.5 / 18.125 | 400 |
| Filter / secondary label | labelMedium | 12.5 / 18.75 | 400 |
| Buttons, menus, fields | labelLarge, control | 13 / 19.5 | 500 |
| Chat bubble | compact | 13.5 / 20.25 | 400 |
| Interface text | bodyMedium | 14 / 21 | 400 |
| Posts and reading | bodyLarge | 14 / 23.1 | 400 |
| Quotes and lists | base + lineHeightContent | 14 / 22.4 | 400 |
| Topic, group, card row title | titleSmall | 14.5 / 19.575 | 600; read topic 500, unread 700 |
| Section title | titleMedium | 17 / 25.5 | 600 |
| Dialog title | titleLarge | 18 / 25.2 | 600 |
| Page title | headlineSmall | 22 / 27.5 | 700 |
| Larger heading | headlineMedium | 28 / 35 | 600 |
| Display heading | headlineLarge | 32 / 40 | 600 |

The 18, 28 and 32px steps complete the hierarchy for Native surfaces absent
from the mockup. Authored h1–h6 use 28, 22, 18, 17, 14 and 14px; weight,
leading and semantic level distinguish adjacent small headings. Do not
introduce another mobile or desktop font scale.

Control presets share text and icon metrics: small 12.5/18.75 with 12px icons,
regular 13/19.5 with 14px icons, large 14/21 with 16px icons. Artwork heights
are 24/34/40px on desktop and 40/44/48px on touch platforms. Touch interaction
bounds stay at least 48px. See `DControlStyle` for scaling and platform rules.

## Zoom and accessibility

`AppTextScaleRegion`, above the Navigator, composes the platform accessibility
`TextScaler` with the app's 80–200% preference. At 100%, the platform scaler
is preserved without a mobile multiplier. Overlays, dialogs, tooltips and
menus inherit the same scaler. Custom measurements use
`MediaQuery.textScalerOf(context)`; never multiply a `TextStyle.fontSize` by
zoom or replace the inherited scaler.

The HTML package still consumes a linear compatibility factor anchored to
14px reading text. It applies that factor internally, so rendered HTML font
sizes already include zoom. Native text retains the full nonlinear scaler.
Relative authored formatting derives from its surrounding style. Zero-size
syntax spans in projected editors remain deliberately invisible.

Rows and controls grow for larger text. Topic metadata and toolbars wrap;
constrained navigation scrolls. Long labels may ellipsize where the component
explicitly owns that policy. Do not squeeze text into a smaller fixed box.

## Native typography API

Import `package:discourse_native/discourse_ui.dart`. `DText` and `DText.rich`
compose native text; `DProse`, `DBlockquote` and `DTextList` provide document
layout. They do not add a second scaler, focus manager or selection owner.

| DTextVariant | Size / line height | Treatment |
| --- | --- | --- |
| h1 | 32 / 40 | 800, -0.025em tracking; balances plain-text headings |
| h2 | 28 / 35 | 600, -0.025em tracking; 1px bottom rule, 8px bottom inset |
| h3 | 22 / 27.5 | 700, zero tracking; page title |
| h4 | 18 / 25.2 | 600, -0.025em tracking |
| paragraph | 14 / 23.1 | Normal reading text |
| lead | 18 / 25.2 | Muted foreground |
| large | 17 / 25.5 | 600 |
| small | 13 / 19.5 | 500 |
| muted | 12.5 / 18.75 | Muted foreground |
| inlineCode | 12.5 / 18.75 | JetBrains Mono, 600 |

`DText.bodyStyleOf` supplies 14/22.4 inherited text for lists, quotes and table
compositions. `DText.linkStyleOf` adds weight, primary color and underline
without changing size. Callers own link recognizers and keyboard actions.
`style` merges intentional customizations after the role. Tracking is resolved
against the inherited scaler because Flutter scales font size but not letter
spacing. `headingLevel` changes semantic hierarchy without changing appearance;
zero opts out. Wrapping, direction and native text semantics are preserved.

`DProse` provides full-width blocks and default article spacing (24px between
blocks, 40px before h2, 32px before h3). Its `spacing` option supports compact
flows. Application post renderers own the reference's 10px paragraph rhythm.
`DBlockquote` supplies a directional rule and inset. `DTextList` provides native
list semantics and bullets or ordered markers (`ordered`, `start`), wrapping
and nested children. Empty flows have zero height. Decorative markers are
excluded from copied text.

Standalone code and `DText.code` share 4px corners, 5px horizontal / 1px vertical
insets and a 1px outline. The approved inline code palette uses 12% foreground
fill and a 24% border. Inline spans use a wrapping rectangular background;
boxed WidgetSpans would compromise text selection and copying. Authored fenced
code and syntax highlighting retain their separate semantic palette.

A host `SelectionArea` owns selection across blocks. Use a focusable Native
control in a WidgetSpan for keyboard-operable inline actions. Styleguide
examples retain the original reference content but render the application
scale; Foundations → Application design scale shows the live semantic roles.

## Verification

`app_text_scale_test.dart` verifies nonlinear scaling, keyboard zoom and reset.
`mobile_text_scale_test.dart` checks the same rendered reading/title/control
sizes in macOS, iOS and Android theme variants, at 320px and every app zoom,
including popup selection and reset. `typography_boundary_test.dart` checks
role inheritance and overlays. The adoption guard prevents new numeric font
sizes outside their designated owners. Platform variants are widget tests,
not device runs. See the design rules' verification record for native review.
