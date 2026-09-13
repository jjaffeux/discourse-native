# Typography

`lib/src/theme/discourse_typography.dart` owns every base font size and the
semantic Material text theme. AppTheme applies it to light, dark, site palette,
and Cupertino themes. Existing app widgets choose a role and override color or emphasis when needed.
The shadcn library uses the same numeric tokens with its reference component
metrics, including explicit weights, tracking and leading.

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

The Native control presets use 12/16 labels for small and regular controls,
and 14/20 for large controls. The application sidebar uses the large preset
for destinations, expandable section headings, More, and Forum/Chat switches:
14/20 text in 32px desktop rows. Counts and the forum URL remain 12/16.
This keeps primary navigation closer to 16/24 topic titles and reading text
at every zoom level. Narrow layouts keep the same type roles and provide larger
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

## Native component API

Import `package:discourse_native/discourse_ui.dart`. `DText` and `DText.rich`
render native `Text` / `Text.rich`; `DProse`, `DBlockquote` and `DTextList`
compose ordinary Flutter widgets. They add no typography scale, text scaler,
networking, focus manager, or selection owner.

| DTextVariant | Size / leading | Weight and treatment |
| --- | --- | --- |
| h1 | 36 / 40 | 800, -0.025em tracking, balanced plain-text heading |
| h2 | 30 / 36 | 600, -0.025em tracking, 1px bottom rule and 8px bottom padding |
| h3 | 24 / 32 | 600, -0.025em tracking |
| h4 | 20 / 28 | 600, -0.025em tracking |
| paragraph (default) | 16 / 28 | Normal weight |
| lead | 20 / 28 | Normal weight, muted foreground |
| large | 18 / 28 | 600 |
| small | 14 / 14 | 500, reference leading-none |
| muted | 14 / 20 | Normal weight, muted foreground |
| inlineCode | 14 / 20 | Bundled JetBrains Mono, 600, muted background |

`DText.bodyStyleOf(context)` supplies the reference's inherited 16/24 body text
for lists, quotes and table compositions. `DText.linkStyleOf(context)` supplies
the demo's inline link treatment (weight 500, primary color and underline) with
no size, so a span inherits its paragraph or lead metrics; the caller owns the
span's recognizer, which also gives it link semantics and a pointer cursor.
`style` merges after the reference style for intentional caller customization.
Sizes remain unscaled; font families and semantic colors come from the live
theme. Tracking is the reference's -0.025em of the rendered size: Flutter
scales font size but not letter spacing, so the inherited scaler is applied to
the tracking when the style is resolved.
`headingLevel` can override semantic hierarchy
without changing visual size: a compact dialog title can use h4 with level 1,
or a section can use large with level 2. Zero opts out of heading semantics.
`semanticsLabel`, `textAlign`, `softWrap`, `maxLines` and `overflow` have native
Text behavior. Text normally wraps without a line limit and inherits direction.

```dart
SelectionArea(
  child: DProse(children: [
    const DText('Community handbook', variant: DTextVariant.h1),
    const DText('Everyone has something to contribute.',
      variant: DTextVariant.lead),
    const DBlockquote(child: Text('“Make room for new perspectives.”')),
    DText.rich(TextSpan(children: [
      const TextSpan(text: 'Open '),
      TextSpan(text: 'community.settings',
        style: DText.styleOf(context, DTextVariant.inlineCode)),
      const TextSpan(text: ' to get started.'),
    ])),
    const DTextList(children: [
      Text('Welcome someone new.'),
      Text('Share a useful resource.'),
    ]),
  ]),
)
```

The host supplies bounded width and scrolling. `DProse` supplies reading style,
full-width blocks and 24px between children, with 40px before h2 and 32px before
h3, without outer margins. Its optional `spacing` overrides these defaults for
compact nested content. `DBlockquote` supplies a leading
rule, directional inset and inherited italic reading text; explicit child styles
can identify an attribution. `DTextList` supplies directional bullets or ordered
markers (`ordered: true`, `start: 9`), native list/item semantics and wrapping
children. Children may include nested lists or native controls. Empty flows and
lists have zero height. Ordered markers are announced; decorative bullets are
not. Markers are excluded from copied text.

A document's existing `SelectionArea` (or the app's route-aware selection area)
owns selection across blocks and spans. For rich inline actions, compose a
focusable native control inside a `WidgetSpan`; a span gesture recognizer alone
is not keyboard focusable. The caller owns recognizers, focus nodes and actions.
Typography itself has no hover, pressed, disabled, loading, overlay or animation
state. Composed controls retain their native focus, activation and lifecycle.

## Official reference and adaptations

The current official Typography MDX and base examples were rechecked on
2026-09-09 at shadcn/ui main
`3ba91b1cc83e1bbe4ab35a422ff2a694849c5048`. They retain h1–h4, p,
blockquote, table, list, Inline code, Lead, Large, Small, Muted and RTL. The
[Typography demo source](https://github.com/shadcn-ui/ui/blob/main/apps/v4/examples/base/typography-demo.tsx)
retains the original composition and utilities. The live documentation URL now
redirects to Typeset and its MDX uses preview references instead of embedding
the example source; Typeset is a separate generated document-styling system and
is outside this catalogue entry. The 2026-09-08 embedded capture remains at
`docs/component-library/reference/typography.md` for reproducibility.

The user's clarification that this is a copy of shadcn supersedes the earlier
adaptation to generic Material typography roles. The table above now matches
the frozen utilities. The same numeric size owner and native scaler remain in
use. Plain h1 text balances up to six lines by finding a narrower measure that
preserves the natural line count without introducing extra breaks within words.
Native font shaping and soft breaks can differ from a browser; rich headings
retain native span layout for selection/copy.
Callers own scroll-to-heading behavior instead of CSS scroll margins. DProse
translates the reference's sibling margins into explicit Flutter block gaps.

Standalone inline code has a muted background with the reference’s fixed 4px
corners and 4.8px horizontal / 3.2px vertical padding. Tailwind’s bare
`rounded` utility is a 0.25rem compatibility value rather than a step of the
theme radius scale, so the corners do not follow the site radius. The box is
painted once; the text carries no second background. Within a
paragraph, `DText.styleOf(context, DTextVariant.inlineCode)` supplies a rectangular
span background so code can wrap, select and copy as text. Using a boxed
WidgetSpan for the code itself would compromise those behaviors. Generic code
uses the reference's muted surface; authored post code retains its distinct
CodeColors and syntax-highlighting contract.

The styleguide's table example uses Flutter `Table` with flexible columns,
16/24 body text, bold headers, 16px/8px cell padding, intrinsic row heights,
TableBorder, alternating token backgrounds, column-header
semantics and start/center/end cell alignment. Flutter owns table/row semantics;
only column-header roles need annotation. Cells wrap to fit the preview instead
of requiring a minimum-width horizontal scroller. This is a documented native
composition, not a competing public table engine. The later Table entry owns
its full reusable API. The reference demo, RTL reference and complete-article
examples reuse that same sample composition with the reference's start-aligned
cells and "King's Treasury" / "People's happiness" header.

The styleguide opens with the frozen `TypographyDemo` composition (including
its primary link and status line after it is followed), the per-section
examples with their original text, and the frozen RTL example: the demo in
Arabic by default with the reference's English and Hebrew translations behind
a language selector whose document sets its own direction. Native
demonstrations follow: headings, reading text, quotes and nested lists, rich
text with a keyboard-focusable action and an LTR code island, the table
composition with mixed alignment, and a complete article.

The core/plugin adoption audit retains control-owned Text styles (button/menu
labels, form fields, badges and metadata), authored HTML/Markdown/composer
renderers, site emoji and inline-link spans, syntax code blocks and specialized
alert/onebox tables. Their density, markup semantics, editing offsets, or domain
interactions have different owners. Settings, shared sheets, add-site, group
management, Chat channel information, Poll/Local Dates/GIF dialogs, Voice room
chat and the event fallback now use the public API for appropriate headings
and secondary prose. Their callbacks, permissions and state remain app-owned.
