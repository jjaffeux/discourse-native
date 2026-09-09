# Typography audit

Audited on 2026-09-09 against the frozen reference. Branch
`claude/audit-typography`, based on main `9c4abfed`.

## References

- Frozen capture `docs/component-library/reference/typography.md`, SHA256
  `3ff202e83d6c90b2521ec471af07cab3c59314028c51ef8d040b3218ec9a9541`. This
  defines scope: the `TypographyDemo`, h1, h2, h3, h4, p, blockquote, table,
  list, Inline code, Lead, Large, Small, Muted and RTL (`TypographyRtl` with
  en/ar/he translations and a language selector).
- Live Markdown <https://ui.shadcn.com/docs/components/base/typography.md>:
  HTTP 200 on 2026-09-09 with the identical SHA256 above. The HTML page
  <https://ui.shadcn.com/docs/components/base/typography> redirects to
  <https://ui.shadcn.com/docs/typeset>; Typeset is supporting material only.
- Registry <https://ui.shadcn.com/r/styles/base-nova/typography.json>: 404.
  The utility classes come from the example TSX in the frozen Markdown.
- Live stylesheet chunks linked from the Typeset page (628,401 bytes
  concatenated) resolved the utilities: `.rounded{border-radius:.25rem}`
  (a fixed compatibility value), `.rounded-sm{border-radius:calc(var(--radius) * .6)}`,
  `--tracking-tight:-.025em`, `.leading-7` = 7 × 4px, `.underline-offset-4{text-underline-offset:4px}`,
  `.text-balance{text-wrap:balance}`, `.scroll-m-20` = 80px,
  `--text-4xl:2.25rem` with line-height `2.5 / 2.25`, `--font-weight-extrabold:800`.
- Semantic tokens: <https://ui.shadcn.com/docs/theming> (`foreground`,
  `muted` / `muted-foreground`, `border`, `primary`, radius scale).

## Reference to Flutter

CSS pixels map to logical pixels at 100% with the 16px root. Colors are the
live `DTokens`; font families come from the theme. The inherited `TextScaler`
is the only scaling owner.

| Reference | Flutter | Result |
| --- | --- | --- |
| h1 `text-4xl font-extrabold tracking-tight text-balance` (36/40, 800, -0.025em, balanced) | `DTextVariant.h1`: 36/40, w800, tracking -0.025 × rendered size; plain text balanced up to six lines while keeping the natural line count and word boundaries | match; tracking at non-100% scale fixed in 7aaae856 |
| h2 `border-b pb-2 text-3xl font-semibold tracking-tight` (30/36, 600, 1px `border` rule, 8px padding) | 30/36, w600, scaled tracking, 1px `DTokens.border` bottom rule outside 8px padding | match |
| h3 `text-2xl font-semibold tracking-tight` (24/32, 600); h4 `text-xl …` (20/28, 600) | 24/32 and 20/28, w600, scaled tracking; semantic heading levels 1–4, `headingLevel` override | match |
| p `leading-7` (16/28); Lead `text-xl text-muted-foreground` (20/28); Large `text-lg font-semibold` (18/28, 600); Small `text-sm leading-none font-medium` (14/14, 500); Muted `text-sm text-muted-foreground` (14/20) | same sizes, leading, weights and colors, zero tracking | match |
| Inline code `rounded bg-muted px-[0.3rem] py-[0.2rem] font-mono text-sm font-semibold` (4px radius, muted, 4.8/3.2px padding, mono 14/20, 600) | standalone: fixed 4px corners, muted box painted once, 4.8/3.2px padding, JetBrains Mono 14/20 w600; span: `DText.styleOf` rectangular background so code wraps and selects | match; radius and double background fixed in 7aaae856 |
| Inline code background height | CSS paints an inline background over the font content area (about 17px + padding); Flutter paints the 20px line box (26.4px) | open, about 3px taller |
| Demo link `font-medium text-primary underline underline-offset-4` | `DText.linkStyleOf`: w500, primary color and underline, no size so the span inherits; caller recognizer gives link semantics and pointer cursor | added in 7aaae856; underline offset open |
| blockquote `mt-6 border-l-2 pl-6 italic` (RTL `border-s-2 ps-6`), inherited 16/24 | `DBlockquote`: 2px directional start rule, 24px start inset, italic 16/24 | match |
| list `my-6 ml-6 list-disc [&>li]:mt-2` (24px text indent, disc marker, 8px between items) | `DTextList`: 16px marker box + 8px gap = 24px indent, 8px item spacing, `•` glyph excluded from selection and semantics; ordered markers spoken | match; glyph instead of CSS disc |
| table `w-full`, collapsed 1px `border` cells, `px-4 py-2`, th `font-bold text-left`, `tr even:bg-muted` (second body row), inherited 16/24, wrapper `my-6 overflow-y-auto` | `Table` with flexible columns, `TableBorder.all` 1px `DTokens.border`, 16/8px cell padding, header w700, muted second body row, start alignment, 16/24 text, column-header and cell roles; cells wrap | match; wrapping instead of a horizontal scroller is intentional |
| Flow: p/blockquote/list/table 24px, h2 40px, h3 32px, `first:mt-0`, li 8px | `DProse`: 24px default, 40px before h2, 32px before h3, no leading or trailing gap; CSS margin collapsing gives the same value for every sibling pair in the demo | match; no outer margins and a 24px gap before h4 (the reference defines none) are intentional |
| `scroll-m-20` (80px scroll margin) | none; the caller owns scroll-to-heading | intentional |
| `transition-colors` on h2 | `MaterialApp` theme animation | not applicable |
| Colors `text-foreground`, `text-muted-foreground`, `bg-muted`, `border`, `text-primary` | `DTokens.foreground`, `mutedForeground`, `muted`, `border`, `primary`, read during build | match |
| RTL `dir`, `border-s`, `ps-6`, `ms-6`, `text-start`, en/ar/he selector defaulting to Arabic | `DDirection` on the document, directional borders and insets, mirrored rows and columns, `TextAlign.start`; `DToggleGroup` selector with the reference's three translations | match; selector and translations added in 7aaae856 |
| Documented examples: demo, twelve sections, RTL | nine styleguide examples: reference demo, section examples with the original text, RTL reference, then native headings, reading text, quote and nested lists, rich text with an LTR code island, table alignment, complete article | match; the demo composition, link and RTL translations were missing |

Implementation review: stateless widgets, tokens and text theme read in
`build`, the balancing `TextPainter` is disposed, no async or cached theme
values, heading and list semantics are correct, every public property is
consumed. `DProse` only recognises direct `DText` children for the h2/h3 gaps,
which its documentation states.

## Issues

1. Fixed in 7aaae856: heading tracking stayed -0.9/-0.75/-0.6/-0.5 logical
   pixels at every zoom because Flutter scales font size but not letter
   spacing; the reference's -0.025em follows the rendered size.
2. Fixed in 7aaae856: standalone inline code used the site base radius; the
   live stylesheet compiles bare `rounded` to a fixed 0.25rem.
3. Fixed in 7aaae856: the standalone code box painted the span background
   beneath its own decoration, doubling a translucent muted token.
4. Fixed in 7aaae856: the balanced h1 measure ignored an inherited
   `DefaultTextStyle.maxLines` and the bold-text accessibility weight, so a
   one-line truncated heading could be narrowed into a shorter ellipsis.
5. Fixed in 7aaae856: the demo's link had no counterpart (`DText.linkStyleOf`
   and a followed-link demonstration).
6. Fixed in 7aaae856: the `TypographyDemo` composition and the RTL example's
   translations and selector were not reproduced; the table example
   abbreviated the header ("Treasury") and the section quotes used curly
   quotes where the reference uses straight quotes. The reference strings are
   generated from the frozen Markdown; the English `level3` keeps the demo's
   "one-liners : 20" spelling in both the demo and the RTL example.
7. Open: `underline-offset-4`. Flutter positions underlines from font
   metrics and `TextStyle` has no offset; a bordered `WidgetSpan` would break
   wrapping and selection.
8. Open: span links take no Tab focus. A span recognizer is not focusable in
   Flutter; the rich example shows the focusable `WidgetSpan` alternative,
   which cannot wrap mid-phrase.
9. Open: the standalone code box is about 3px taller than the CSS inline
   background (line box versus content area). A font-metric box would vary by
   host font, and the 14/20 role is pinned by `typography_boundary_test.dart`.
10. Intentional: `•` glyph marker, wrapping table cells, no `DProse` outer
    margins, 24px before h4, and no scroll margin, each recorded above.
11. Pre-existing and out of scope, reproduced with the base sources of
    `d_typography.dart` and `typography_examples.dart`:
    `test/typography_boundary_test.dart` expects the DButton small label at
    14px while `DButton.fontSizeFor(small)` renders 12.8px;
    `test/discourse_typography_adoption_test.dart` reports font-size literals
    in `d_questionnaire.dart`, `d_data_table.dart`, `d_avatar.dart` and
    `d_radio_group.dart`; `test/poll_composer_panel_test.dart` "an open date
    dialog cannot apply during submission" fails to find its date field.

## Verification

- `dart format --output=none --set-exit-if-changed lib/src/ui/components/d_typography.dart lib/src/styleguide/examples/typography_examples.dart test/ui/d_typography_test.dart test/styleguide/typography_examples_test.dart`:
  0 changed.
- `flutter analyze --no-pub`: No issues found.
- `flutter test --no-pub --test-randomize-ordering-seed=random test/ui/d_typography_test.dart test/styleguide/typography_examples_test.dart test/styleguide/styleguide_page_test.dart test/ui/d_label_test.dart test/ui/d_field_test.dart test/app_settings_page_test.dart test/add_instance_sheet_test.dart test/add_instance_lifecycle_test.dart test/chat_channel_info_view_test.dart test/gif_picker_test.dart test/event_card_test.dart test/event_card_lifecycle_test.dart test/group_page_test.dart test/plugins/poll/poll_composer_sheet_test.dart test/plugins/local_dates/local_date_composer_sheet_lifecycle_test.dart test/plugins/local_dates/local_date_composer_component_test.dart test/empty_native_fixture_test.dart`:
  160 passed, seed 176774401. These include every app caller of `DText`
  (`DLabel`, `DField`, Settings, Add a site, Chat channel information, GIF
  picker, Events, group management, Poll and Local Dates composers, Empty).
- `flutter test --no-pub test/typography_boundary_test.dart test/discourse_typography_adoption_test.dart test/poll_composer_panel_test.dart`
  with the base `d_typography.dart` and `typography_examples.dart` restored:
  the same four failures as with this branch (issue 11).

No shared foundation, token, theme, export, lockfile or Flutter pin changed.
This is a source-level audit backed by widget tests; no device or browser
rendering was performed.
