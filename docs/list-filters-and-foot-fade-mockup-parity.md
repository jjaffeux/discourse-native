# List filters and foot fade parity

The topic-list header reference is `discourse-native-mockups` commit
`7d7fd88`, `src/App.tsx` (`listViewFor`, `ViewSwitch`, `CategoryPath`,
`FilterPill`, `FitRow`, and `useFlip`) and `src/app.css` (`.fit-row`,
`.view-switch`, `.picker-quiet`, `.pill-count`, and `.picker-path__sep`).
The foot fade below retains its earlier reference.

## Header composition

The feed switch, category path, Tags, and Filters form one adaptive row.
The notification action stands outside that row, aligned with its first line,
including with enlarged text. Its trigger retains its chevron on phones.
The app shows notification settings when a category supplies a real target;
the reference also draws an inert bell on unscoped lists.

All controls use the Native kit. The page has no extra toolbar fill or divider.
Quiet controls have the palette's faint foreground fill. Selected taxonomy
and filter controls use the raised surface. Category segments share one pill.

| Measurement | Desktop | Phone | Retracted phone header |
| --- | --- | --- | --- |
| Filter height | 30 | 36 | 36 |
| Filter text | 12.5 | 14 | 14 |
| Ordinary filter side inset | 10 plus transparent border | 12 | 10 |
| Switch segment height | 26 | 32 | 32 |
| Switch track inset / segment gap | 2 / 2 | 2 / 2 | 2 / 2 |
| Switch segment side inset | 10 | 10 | 0 for an uncounted glyph |
| Row gap | 8 | 8 | 6 |
| Gap between wrapped lines | 8 | 8 | 8 |
| Breadcrumb separator side inset | 5 | 5 | 2 |

Width pressure and phone header retraction are independent states.
`DFitRow.tightOf` asks eligible labels to shorten; `DFitRow.compactOf` reports
phone header retraction. Only compactness changes the row gap, phone pill
insets, and breadcrumb separator insets.

## The five fit stages

| Stage | Labels | Row policy |
| --- | --- | --- |
| `full` | Full | One line at each control's natural width |
| `tight` | Shortened | One line at each control's natural width |
| `wrapped` | Full | Feed switch on its own first line |
| `wrappedTight` | Shortened | Feed switch on its own first line |
| `isolated` | Shortened | Category path on its own last line; feed switch shares the first |

Overflow advances either unwrapped stage. More than two runs advances either
ordinary wrapped stage. Each stage records the width needed to return to its
predecessor. Changed content or compactness resets those measurements.
Popup content does not contribute to a control's natural width.
The app resolves these stages during layout before painting an overflowing row.
Long controls remain bounded by the available line.

## Feed switch

The view order is Latest, Unread, New, Unseen, Top, and Trending. The current
view remains visible. Up to three segments fit beside the overflow trigger;
fitting stops at the first view that cannot fit. The app omits personal views
for signed-out readers and uses the forum's New and Top configuration.

Only a retracted phone header replaces feed labels with icons. Width pressure
alone retains their names. The marks are the mockup's solid clock, envelope,
certificate, eye slash, trophy, and fire. A zero-count glyph segment is square;
a counted segment retains its icon, 6-point gap, and count. The selected segment
uses the raised surface and semibold text. Hidden labels retain accessible
names and full-name tooltips.

New and Top open their submenus. Phone overflow offers all available views;
desktop overflow offers the hidden views. Counts on hidden views describe their
union. Unified New overlaps Unread, while legacy New and Unread are disjoint.

`DBadgeSize.count` owns header count geometry. `DBadgeSize.menuCount` retains
the menu's desktop typography on phones, as `.filter-menu__count` does.

| Count measurement | Desktop header and menus | Phone header |
| --- | --- | --- |
| Font size / line height | 11.5 / 16 | 12.5 / 18 |
| Weight / digits | 600 / tabular | 600 / tabular |
| Minimum width | 20 | 20 |
| Vertical / horizontal inset | 1 / 7 | 1 / 7 |
| Surface | Borderless accent pill | Borderless accent pill |

Count colors follow Native's semantic accent tokens. The reference's separate
raw-accent tint and readable accent text can differ from these tokens in custom
palettes. The widget checks verify the Native token contract, not identical
pixels across browser and Flutter theme resolution.

## Category, tag, and filter pills

Every selected category level keeps its own mark and menu. A trailing deeper
level exists only when children are available within the site's nesting limit.
It says Subcategory, or No subcategories for an exact category clause.
Shortened paths keep the selected leaf's name and reduce their ancestors and
the deeper level to marks. Retracted phone headers reduce every level to a mark.
The unselected Categories placeholder remains a word until retraction.
Each segment is at most 180 points wide. Separators are rounded 1.5 by 14
point Native lines rotated 18 degrees, with noninteractive space beside them.

Unselected Tags becomes a glyph under width pressure. Selected tag text stays
until phone retraction. Tag text is limited to 88 points. Filters keeps only
its active-clause count when shortened, or only its glyph when empty. Its full
label is limited to 96 points. Active counts include category and tag clauses.
Glyph-only actions retain their full accessible names and tooltips.

Category and tag menus edit only their own filter scopes. The main Filters
menu retains its draft/apply flow. Reflow retains menu owners, focus nodes, and
buttons. Removing an ancestor inside an open category editor hands ownership
to the remaining path instead of dismissing the editor.

## Retraction motion

Compact transitions last 260 ms. Row bounds use cubic-out easing
`1 - (1 - t)^3`; retained nested controls translate with
`cubic-bezier(.2,.8,.2,1)`, and new controls fade with `ease`.
Native keeps controls laid out at their destination sizes while easing row
bounds and translating individual controls, without scaling text or glyphs.
Internal control-motion markers are active only under a fit row.
The inset feed-switch background paints at its interpolated frame size while
its segments keep their destination layout sizes.
Their paint, hit-test, and semantics transforms share the same translation.
Interrupted transitions start from the currently drawn positions. Reduced
motion applies the destination layout immediately.

## Focused verification

`test/topic_list_responsive_filters_test.dart` renders the production filter
components with real fonts and checks expanded/scrolled phones, narrow deep
paths, filter counts, retained editors, and accessible text scaling.
Set `RESPONSIVE_FILTER_REVIEW_DIR` to export its PNG captures.
`test/d_fit_row_test.dart` checks fitting stages, nested artwork without scale,
mid-transition pointer activation, retained elements, and motion curves.
Its track check reads rendered pixels inside the intermediate background and
outside the settled background.
The badge, button, toggle, control-wrap, feed-menu, category-path, navigation,
and taxonomy menu suites pin the corresponding Native and application behavior.
These are widget renders, not physical-device or zero-pixel-difference claims.

## The fade under the bar

On a phone the lists run on under the bar to the screen's edge. From the
bar's top margin edge down they thin linearly to 30% at the foot. They are
never fully gone, so they still read past the bar. This replaces a list's
20 px bottom edge fade, and applies whether or not the list continues.

| Part | Mockup | App |
| --- | --- | --- |
| Band | `#000` at `100% - --dock-now`, `rgb(0 0 0 / .3)` at `100%` | Same stops on the scroller's existing `ShaderMaskLayer` |
| `--dock-now` open | The dock float's height: the bar and its top margin | `DMobileDockGeometry.footerExtent`, 92 at a foot of 34 and the default scale |
| `--dock-now` folded | The float around the circle in its corner | `inset + circle + cornerAt(circle)`, 67.32 at a foot of 34 |
| Which scrollers | `.head-mask`: lists, the topic, chat | Every vertical scroller whose bottom is the foot the bar floats at |

`DMobileDock` wraps its bar in a `DScrollFootCover`, which reports the bar's
laid-out height plus `geometry.margin.vertical` as it folds and unfolds. The
phone's `DScrollChrome` publishes that as a `DScrollFoot`, and
`DScrollBehavior` applies it to each vertical scroller under the chrome.
A footer without a dock reports nothing, so a route that hides the dock has
no band. A page that keeps its own room at the foot, such as a chat
transcript fading into its composer through `DScrollFadeScope.bottomInset`,
keeps its own fade. The band also goes while the footer is put away or the
sidebar takes its place.

The scrollers already paint through a `ShaderMaskLayer` for their edge
fades, so the band adds no layer. When the bar folds, the band's stops
change and the mask repaints. The list's own artwork is retained.
`mobile_scroll_performance_test.dart` and
`topic_sheet_scroll_performance_test.dart` pass unchanged. Their paint
totals rise by one paint of the new pass-through box each time the dock
paints (2,574 to 2,620 dock paints in the topic sheet profile). The list's
own counts are unchanged.
