# Application design rules

Reference: `http://localhost:5183/`, audited 2026-09-23. These rules supersede
older shadcn measurements where they describe the same application surface.
The source is the local `discourse-native-mockups` project at
`ec6118648838baf80f8cbca0a6543c841d89659c`. The captured file hashes, every
palette declaration, and **767 style records** with owner names, source lines,
element names and exact expressions are in [reference-metrics.json](reference-metrics.json).
An expression is retained verbatim when its value depends on state or width.
The inventory includes icon sizes; those are not extra text styles.

## Evidence and scope

The browser pass covered the topic list and reader, Groups, Badges, Bookmarks,
Users, Messages, Events in Month and Schedule modes, the expanded Forum and
Chat sidebars, a channel conversation with inline threads, and filter menus.
Desktop was inspected at 1280px wide and mobile at 390px wide. The mobile list
and channel retained the desktop text sizes. Dracula was inspected in dark
and light modes. All other palettes, responsive branches, composer layouts,
notification/account menus, and toolbar variants were inventoried from source.
Source inspection and native verification are distinct; the verification
record below describes what actually ran.

The rules below cover the whole reference: typography, geometry, spacing,
color, borders, state, motion, responsive behavior and overflow. Source-only
recipes are identified where the reference has no corresponding Native
component or where app behavior needs a native adaptation. Application data,
permissions, routing and editing ownership stay in their existing adapters.

## Units and scaling

- Measurements are Flutter logical pixels / browser CSS pixels at 100%.
- There is one unscaled typography system on every platform. No mobile 120%
  multiplier and no second multiplier in text styles or child widgets.
- The root composes the platform accessibility scaler with the user's 80–200%
  app zoom. Measurements use the same inherited scaler as painted text.
- Touch controls reserve at least 48×48px interaction bounds. The compact
  artwork may be smaller. Adjacent hit regions must not overlap.
- Text and controls grow or wrap at increased text size. A fixed height is a
  minimum for controls; it is not permission to clip text.
- Numeric typography constants belong to `DiscourseTypography`, control
  geometry to `DControlStyle`, shape to `DRadius`, and repeated insets to
  `DInsets`. App widgets choose roles and presets instead of introducing sizes.

## Typography

The reference uses the system sans-serif family. The app retains the selected
forum/system font; code uses bundled JetBrains Mono. Text tracking is zero
unless explicitly shown below. Page titles are bold; body copy is normal.

| Role | Size | Line height | Weight | Native owner |
| --- | ---: | ---: | --- | --- |
| Tiny category/tag/count labels | 11 | 16.5 | 400–700 by state | `micro` |
| Byline, last poster, chat metadata | 11.5 | 17.25 | 400–500 | `metadata`, `labelSmall` |
| Dates, timestamps, secondary counts | 12 | 18 | 400 | `xs`, `bodySmall` |
| List excerpt | 12.5 | 18.125 | 400; 600 for unread chat preview | `preview`, `DItemDescription` |
| Filter label / secondary label | 12.5 | 18.75 | 400, leading filter 600 | `labelMedium`, small controls |
| Menu, button, field, tab label | 13 | 19.5 | 400; action 500–600 | `control`, `labelLarge` |
| Chat bubble / directory text | 13.5 | 20.25 | 400 | `compact`, conversation Bubble |
| Interface text / author name | 14 | 21 | 400 / 600 | `bodyMedium` |
| Post paragraph / Native editor | 14 | 23.1 | 400 | `bodyLarge`, default `DText` |
| Quote, list item | 14 | 22.4 | 400 | `lineHeightContent` |
| Topic, bookmark, badge, group title | 14.5 | 19.575 | 600; topic read 500 / unread 700 | `titleSmall`, `DItemTitle` |
| Composer title / small section title | 17 | 25.5 | 600 | `titleMedium` |
| Dialog or larger section title | 18 | 25.2 | 600 | `titleLarge` |
| Page / topic-reader / channel title | **22** | **27.5** | **700** | `headlineSmall`, `DText.h3` |
| Larger authored heading | 28 | 35 | 600 | `headlineMedium`, `DText.h2` |
| Display heading | 32 | 40 | 600; DText h1 800 | `headlineLarge`, `DText.h1` |

The reference has no long-form h1–h6 specimen or general dialog specimen.
The 18/28/32 steps complete the application hierarchy; they are deliberate
extensions, not claimed browser measurements. Authored HTML/Markdown h1–h6
use 28, 22, 18, 17, 14, 14 with their matching leading. Semantic heading level
is independent of visual size. The inherited family, colors and text scaler
remain authoritative. DText display/article headings retain -0.025em tracking;
page titles use zero tracking, matching the measured h1.

Native `DText` paragraph is 14/23.1; list/quote body is 14/22.4; small is
13/19.5; muted and inline code are 12.5/18.75. Lead text is 18/25.2.
The styleguide Foundations → Application design scale renders the live roles.

## Radius system

| Value | Role | Rule |
| ---: | --- | --- |
| 0 | Flush list rows, attached edges, quote leading edge | Avoid rounded highlights in full-width lists |
| 2 | Category swatch, small square marker | `DRadius.marker` |
| 3 | Calendar strips, bar chart fill | Keep tiny marks distinct from controls |
| 4 | Inline code, close affordance | `DRadius.code` |
| 6 | Nested segmented control, small thread action | `DRadius.nested` |
| 7 | Popup item highlight | `DRadius.menuItem` |
| 8 | Standard button/input/select, navigation row, quote trailing edge | `DRadius.control` |
| 10 | Popup/menu container, unread count capsule | `DRadius.popover` |
| 12 | Standard bubble, active community tile | `DRadius.bubble` |
| 14 | Main panels, sheets, detached footer, current mobile navigation tile | `DRadius.panel` |
| 19 | Chat message bubble; joined corners use one quarter of this radius | `DRadius.chatBubble` |
| 999 / 50% | Pills, tags, circular avatars, mobile primary action | `DRadius.pill` or circular avatar owner |

Radii are fixed geometry, independent of forum palette radius settings. The
avatar component retains the configured forum avatar shape. Attached groups
round only their outside corners. A footer attached to a panel rounds its
exposed top corners, clips its fill to that outline, and draws one top border.
A floating panel rounds all four corners. A full-screen editor has square
window-adjoining edges. The desktop reference's primary button is 8px and
mobile primary is a pill; the app retains its accepted primary pill treatment
on both platforms so variant shape remains predictable. This is a recorded
native design choice, not a source measurement.

## Spacing and insets

General spacing: **2, 4, 8, 12, 16, 24, 32**. Use named roles for repeated
intermediate measurements instead of forcing every relationship onto 8px.

| Relationship | Rule |
| --- | --- |
| Page heading/container | 16px all sides (`DInsets.page`) |
| Full-width list row | 12px vertical, 16px horizontal (`DInsets.listRow`) |
| Header filter group | 8px gap; 16px side margin; 14px below controls; 16px below separator |
| Separate toolbar actions | 6px gap (`DSpacing.controlGap`) |
| Inline control icon → label | 4px small/regular, 6px large; source commonly 6px |
| List title → excerpt | Source 5px; Native row flow uses 6px |
| Excerpt → metadata | Source 7px; Native row flow uses 6px |
| List leading avatar → text | 10px |
| Menu outer padding | 6px (`DInsets.menu`) |
| Menu item padding | 7px vertical, 8px horizontal (`DInsets.menuItem`) |
| Menu icon → label | 8–9px; reserve a 16px icon column |
| Menu offset from trigger | 6px, flipped/shifted at viewport bounds |
| Menu group divider | 1px line plus 4px vertical separation |
| Post container | 16px all sides |
| Author avatar → author | 9px; body aligns at avatar width + gap = 39px |
| Post paragraph vertical margin | 10px, collapsed between ordinary paragraphs |
| Quote box | 10px vertical / 14px horizontal; 12px outer vertical margin |
| Quote author → body | 6px; author avatar gap 7px |
| Bulleted list | 20px indent, 6px between items, 10px outer vertical margin |
| Inline code | 1px vertical / 5px horizontal, 1px outline |
| Chat bubble | 8px vertical / 12px horizontal (`DInsets.bubble`) |
| Chat avatar → bubble | 9px; metadata → bubble 4px |
| Same-author messages | 3px vertical gap |
| New message group | 14px gap; major/thread boundary 28px |
| Directory cells | 8px vertical / 16px horizontal; 16px column gap |
| Empty state | 24px vertical / 16px horizontal |
| Standard content section | 16–24px; major sections 32px |
| Desktop workspace gutter | 6px; drag divider sits in the gutter |

Use directional insets and leading/trailing alignment so the same hierarchy
works in RTL. Insets are layout; radii and interactive visuals belong to the
kit. Content can override spacing for a documented composition, but controls
must not acquire local height/padding wrappers.

## Controls, icons, fields and menus

| Size preset | Desktop artwork | Touch artwork | Text / leading | Icon |
| --- | ---: | ---: | ---: | ---: |
| Small | 24 | 40 | 12.5 / 18.75 | 12 |
| Regular | 34 | 44 | 13 / 19.5 | 14 |
| Large | 40 | 48 | 14 / 21 | 16 |

The general scale remains available across Button, Toggle, Select, Input,
Input Group, Combobox, Tabs and Menubar triggers. Application controls use the
[measured mockup presets](control-size-parity.md): `filter` 30.75px, `field`
35.5px, `preference` 40.25px, `chip` 24px, `toolbar` 34px, `segment` 28px,
`chrome` 25px and `action` 34px desktop / 44px mobile. These supersede the earlier
normalization of filters and fields to the regular size. Text scaling expands
artwork; invisible touch targets remain at least 48px. Preference switches use
`DSwitchSize.preference` (38×22px with an 18px thumb).

- Primary actions use the muted accent fill, outline actions use a quiet
  neutral fill and 1px border, transparent actions reveal a fill on hover.
- Icons inherit foreground and semantic disabled state. Font Awesome source
  `fontSize` values describe artwork height, not text size. Tiny 7–11px
  chevrons/sort marks remain decorative and share their parent's hit target.
- Input labels/hints use the control role. Borderless composer title/body
  explicitly use their text roles. Input geometry must grow for text scaling.
- Buttons do not translate on hover/press. Native keyboard focus has a 1px
  ring with 2px separation. Disabled controls cannot activate.
- Regular popup artwork is 33.5px (13px × 1.5 + 14px inset). Native compensates
  for Flutter paragraph rounding rather than rounding up the entire row.
  Touch interaction bounds remain at least 48px. Text scaling grows both.
- Popup corners are 10px, item highlights 7px, padding 6px, outline 1px.
  The default popup has no shadow. Explicit medium/large shadows remain
  available for components that deliberately request elevation.
- Popup width follows content/anchor, with reference minimums 186–190px and
  typical maximum height 280px. Collision and safe-area handling win over
  preferred placement. Searchable/native sheets keep their existing ownership.
- Hover changes paint immediately. Persistent selection uses a check/mark;
  a moving highlight must not leave two rows highlighted during a transition.

## Surfaces, borders and palette rules

The reference declares Discourse `primary` as text, `secondary` as background,
`tertiary` as accent. Light/dark swap the first two for the selected scheme.
All mixes below are in sRGB. Existing Native palette adapters own contrast
repairs and must preserve legibility; the literal reference's muted colors
are not a mandate to remove those repairs.

| Semantic role | Formula |
| --- | --- |
| Panel | 3% text + 97% background |
| Backdrop / sunken | 86% background + 14% black |
| Raised | 10% text + 90% background |
| Footer | 5% text + 95% background |
| Subtle / normal / strong border | 12% / 22% / 32% text mixed into background |
| Strong / ordinary text | 100% / 90% text |
| Secondary / muted / dim / dimmest text | 62% / 50% / 40% / 32% text |
| Accent fill | 25% accent + 75% background |
| Accent fill foreground | 50% accent + 50% text |
| Accent hover | 80% accent + 20% text |
| Selected list tint | 12% accent over surface |
| Hover / pressed overlay | 8% / 13% text over surface |
| Success / danger fill | Same 25% fill / 50% foreground formula with semantic hue |
| Scrim | Black at 45% |

Category colors and avatar identity are content colors. Keep them separate
from the UI state ramp. Ordinary outlines and row separators are 1px. Selected
full-width rows have a 3px directional accent edge. Quote bars are 3px.
Selection outlines and focus rings must not shift layout. No default drop
shadows appear in the captured reference; separation comes from the palette,
border and spacing. Inline code in the app retains the approved stronger
12% fill / 24% border so it remains visible inside neutral chat bubbles.

## Page and component recipes

| Family | Composition and measurements | Native application |
| --- | --- | --- |
| Topic list | 22px title, filter row/divider, 12×16 rows; 14.5px titles; 12.5px two-line excerpts; 11–12px metadata; 22px last-poster avatar | Shared topic row, full-width Item, theme roles |
| Topic reader | 16px heading inset, 22px title, taxonomy/actions, 12.5px stats; date chip; 16px posts, 30px author avatar, 14px prose | TopicInboxHeader, CookedHtml, existing post adapters |
| Private messages | Same title/filter/row system, inbox and scope selectors; private-conversation metadata | Shared topic list and message adapters |
| Bookmarks | 34px circular type mark, 10px gap, 14.5px title, 12.5px location; expired item gets 3px selected edge | Existing bookmark rows and Item/title roles |
| Badges | 13px bold section label with 6/16/8 inset; 34px emblem, 14.5px name, 12.5px tier/description; earned check | Existing badge page and shared roles |
| Groups | 34px mark, name/handle, 11px member pill, 12.5px two-line description; overlapping 22px avatars at -6px | Existing group adapters, Avatar, Badge, Item |
| Users | 22px title; wrapping filter bar; 170px identity/text columns, 132px numeric columns, 16px gaps; 13.5px cells, 13px numeric values, 20px bar | DataTable with horizontal overflow, app column model |
| Events month | 22px title; filters then previous/month/next row; seven equal columns; 11px uppercase weekday labels, 0.4 tracking; 28px date lane | Kalender-backed Calendar retains its engine and semantics |
| Events schedule | 16px page inset; date group and time column; accent event bar; 13.5–14px text and 12px secondary details | Existing event calendar/list adapters |
| Chat list | 40px avatar/hashtag mark, 10px gap; 14.5px name, 12px time, 12.5px preview; unread via weight | Existing chat list and theme roles |
| Chat conversation | 22px title, 12.5px stats, 28px avatars, 13.5/20.25 bubbles; width capped at 76%; 12px corners and 8×12 inset | Conversation Bubble variants, Message layout |
| Chat thread | Thread preview pill, 18px overlapping avatars; indented replies, bounded reply field; 12–13px metadata | Existing inline thread composition |
| Composer | Docked left/right/bottom or full-screen; title 17px; body 14/22.4 (mobile reference 14.5/22.475); category/tag row; 34px tools, 8px tool gap | Native editor uses 14/23.1 and 17px title on every platform; owns focus/selection and draft state |
| Sidebar | 14px destinations, 12px counts, 13px icons; same text in expanded/mobile sidebar; collapse/category hierarchy | Sidebar presets and existing shell ownership |
| Desktop tab strip | 56px row, 35px pill tabs with 13px labels and 12px icons; 30px recent-tabs and add buttons; 18px close action; 6px tab gaps and 170px width cap | Document Tabs and existing tab model |
| Community rail | Circular/rounded community tiles, active 12px corners, text initials proportional to tile | Existing avatar/site switcher |
| Mobile navigation | 44px primary pill; active tile14px vs inactive pill; header and safe-area-aware bottom dock | Native mobile shell, accessible targets |
| Notifications | Bounded popup, 13px title/text, 12.5px filters, 13/17.55 row copy, 11px count markers | Existing notification adapters and popup roles |
| Account / presence / topic admin | Popup + groups/rows; 13px labels, 6px popup padding; destructive role where applicable | Dropdown Menu / Context Menu |
| Empty / filtered list | 13.5px muted copy, 24×16 inset, no placeholder control | Existing Empty states |

These recipes describe layout, not mock data or new product features. Source
screens without a matching application route do not require invented routes.
Native tables/calendars/editors keep their established scrolling, selection,
keyboard and data engines. Use the recipe to style those owners.

## Responsive and overflow rules

The source switches at **713px** (53px rail + 240px minimum sidebar +
420px minimum list). The sidebar can grow to 460px; a reader needs 380px
and a side composer 320px. Splitting therefore needs 800px of content, and
side docking 740px. These are layout thresholds, not font scaling. The source allows a resizable reading
pane and left/right/bottom composer. Mobile shows one content pane, opens
content inward, wraps topic metadata and filters, and defaults the calendar to
Schedule. A user's selected calendar mode overrides that default.

- Decide content wrapping from available pane width, not just window width.
- Page headers, filters and body share a 16px horizontal content edge.
- Topic titles can wrap; excerpts clamp at two lines at ordinary zoom and grow
  at large accessible text. Dates stay together. Metadata wraps onto another
  line when it cannot fit.
- Directory tables scroll horizontally; do not compress labels below the type
  scale. Calendar strips omit labels when columns cannot hold useful text.
- A composer action label disappears when its own slot is too narrow (source
  action block threshold116px), while its accessible name remains intact.
  The source bar's480px threshold is a composition breakpoint, not typography.
- Main viewport and pinned footer retain independent layout. Safe areas,
  keyboard insets and system navigation are handled by the Native shell.
- Menus flip/shift and scroll within the available viewport. Avoid extra scroll
  owners inside controls. Header retraction follows deliberate body scrolling.

## Motion and interaction

Source motion inventory: hover/close affordances120ms; row background100ms;
chat grouping220ms; sidebar width240ms; page sideways260ms, inward280ms,
fade160ms; composer bottom entry300ms, side entry220ms, bottom exit240ms,
side exit190ms. Entry uses cubic-bezier(.32,.72,0,1); exit (.4,0,1,1).
Reduced-motion media disables view/composer animations.

Native rules preserve the app's immediate interactive-row paint and existing
navigation transition owner. Do not interpolate two menu/list highlights.
Respect reduced motion in every new animation. Keep focus, selected state,
editing caret, loading and disabled behavior independent of hover. Tooltips
supplement accessible labels. A glyph's small artwork does not shrink its
focusable target. No decorative text takes an extra focus stop.

## Adoption and verification

This change implements the shared type scale, removes the mobile baseline,
unifies control text/icon metrics, updates desktop presets, centralizes
radii/insets, adopts the reference's popup and list geometry, updates topic
page headings and row typography, and adds a live Foundations specimen.
The machine-readable inventory preserves page-specific source values even
where the application uses an existing specialized layout owner. Touch
geometry, primary pills, contrast repairs, editor body leading, editor engine
and navigation motion are the explicit Native adaptations above.

### Verification — 2026-09-23

- Flutter 3.47.4 / Dart 3.13.3, matching the repository's `.fvmrc`; no dependency
  or SDK-pin changes. Formatting and `git diff --check` passed.
- `flutter analyze --no-pub`: no issues.
- **400 focused tests passed**: 399 in the shared-system batch below, plus
  the app settings hydration test in `site_theme_app_test.dart`.
- Coverage includes every app zoom, macOS/iOS/Android theme variants at 320px,
  native/cooked text parity, nonlinear platform scaling, touch edge taps,
  keyboard navigation, popup collision/scrolling/selection, row selection,
  RTL, scaled excerpts, composer docking, editor scrolling and keyboard insets.
- Updated 18 golden images after rendered inspection: four palettes ×
  desktop rest/hover/open + mobile controls, and light/dark topic rows. Golden
  typography uses bundled JetBrains Mono for reproducibility; native review
  uses the platform font. Golden viewports: 720×480 controls, 390×900 touch
  controls and 680×580 topic rows.

```sh
flutter test --no-pub \
  test/app_text_scale_test.dart test/app_theme_test.dart \
  test/mobile_text_scale_test.dart test/mobile_control_scale_test.dart \
  test/control_size_scale_test.dart test/typography_boundary_test.dart \
  test/ui/d_typography_test.dart test/discourse_typography_adoption_test.dart \
  test/d_item_test.dart test/d_select_test.dart test/ui/d_card_test.dart \
  test/ui/d_bubble_test.dart test/ui/d_combobox_test.dart \
  test/d_popover_test.dart test/d_dropdown_menu_test.dart \
  test/control_consistency_test.dart test/control_consistency_golden_test.dart \
  test/compact_topic_list_test.dart test/full_width_topic_row_test.dart \
  test/topic_row_status_alignment_test.dart \
  test/styleguide/typography_examples_test.dart \
  test/composer_docking_test.dart test/composer_panel_controls_test.dart
flutter test --no-pub test/site_theme_app_test.dart \
  --plain-name 'hydrates an injected app-wide settings store on startup'
```

Native review used `tool/topics_redesign_review_main.dart`, built as an isolated
macOS debug app with mock data, separate bundle identity and the repository's
permitted debug entitlements. Signature validation and actual launch passed.
Inspected: wide dark topic list, 390px light/dark rows, 390px at 200% text,
filter popup opening/scrollable geometry, reader heading and loading-error
state, Foundations' live typography/radius/row specimen, and Button's Control
consistency example including popup selection (Bugs → Support). The fixture
does not supply ready reader posts or mount its composer, so native post-body
and composer editing were not verified there; their focused widget checks passed.
No iOS/Android simulator or device run is claimed.

Final native rebuild kernel SHA256:
`557b0c0be238b87794a7692515b2484313a88f996a78df5a054bd113436b84b5`.
The isolated review app was closed after inspection.

The broader `site_theme_app_test.dart` run has **nine existing failures** that
also reproduce in an unchanged checkout of base `de9b76d39`: removed
`settings-rail-button` finders and obsolete rail `AnimatedContainer`/shape
expectations. They are outside this design change; its settings hydration
check passes. An existing composer docking assertion for visible “Discard”
text also failed on that base; it now checks the existing tooltip, preserving
the accessible-action assertion. The focused suite above passes in full.
