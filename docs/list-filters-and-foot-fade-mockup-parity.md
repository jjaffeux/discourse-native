# List filters and foot fade parity

The topic-list header reference is `discourse-native-mockups` branch
`test-mobile-layout` at `9b59748`, `src/App.tsx` (`listViewFor`,
`ViewSwitch`, `CategoryPath`, `FilterPill`, `FitRow`, and `useFlip`) and
`src/app.css` (`.fit-row`, `.view-switch`, `.two-way`, `.picker-quiet`,
`.view-pick`, `.pill-count`, and `.picker-path__sep`). Its phone view pill,
glyph-only Categories, and closer retracted row come from `cd5cd18`, which
supersedes `79214cb`'s phone switch; the fresh fitting comes from `9b59748`.
The foot fade below retains its earlier reference.

## Header composition

The view control, category path, Tags, and Filters form one adaptive row.
On a desktop the view control is a switch; on a phone it is one quiet pill.
The notification action stands outside that row, aligned with its first line,
including with enlarged text. Its trigger retains its chevron on phones.
The app shows notification settings when a category supplies a real target;
the reference also draws an inert bell on unscoped lists.

All controls use the Native kit. The page has no extra toolbar fill or divider.
Quiet controls have the palette's faint foreground fill. Selected taxonomy
and filter controls use the raised surface. Category segments share one pill.

| Measurement | Desktop | Phone | Retracted phone header |
| --- | --- | --- | --- |
| Filter height | 30 | 44 | 44 |
| Filter text | 12.5 | 16 | 16 |
| Ordinary filter side inset | 10 plus transparent border | 12 | 10 with a path, else 12 |
| View pill side inset / name-to-count gap | None | 12 / 7 | 12 / 7 |
| Switch segment height | 26 | None | None |
| Switch track inset / segment gap | 2 / 2 | None | None |
| Switch segment side inset | 10 | None | None |
| Row gap | 8 | 8 | 6 with a path, else 8 |
| Gap between wrapped lines | 8 | 8 | 8 |
| Breadcrumb separator side inset | 5 | 5 | 2 |

The phone height and text are the app's own 44 and 16 (since `617f14c24`),
larger than the reference's 36 and 14.

Width pressure and phone header retraction are independent states.
`DFitRow.tightOf` asks eligible labels to shorten; `DFitRow.compactOf` reports
phone header retraction, which turns labels into marks. The row stands closer
only while it also holds a category path with separators: the filter bar sets
`DFitRow.closeUp` then, and `DFitRow.closedUpOf` gives the 6-point row gap and
the 10-point quiet pill insets. A row with nothing to shorten does not shift as
the header retracts. The view pill, the row's leading item, keeps its insets
either way, so its size does not change with the header.

## The five fit stages

| Stage | Labels | Row policy |
| --- | --- | --- |
| `full` | Full | One line at each control's natural width |
| `tight` | Shortened | One line at each control's natural width |
| `wrapped` | Full | View control on its own first line |
| `wrappedTight` | Shortened | View control on its own first line |
| `isolated` | Shortened | Category path on its own last line; view control shares the first |

Overflow advances either unwrapped stage. More than two runs advances either
ordinary wrapped stage. Stages only advance. Once the row settles, any change
in its room or in a control's width (a count appearing, a name changing) fits
it again from `full`, as the reference's `FitRow` does since `9b59748`; a
width remembered for stepping back says nothing once a pill has changed. The
row records its width and each control's width at the stage it settles on. A
later layout whose first pass differs at that same stage restarts; the
widths a stage itself changes are never taken for new content. Rebuilt
content or compactness also restarts from `full`.
Popup content does not contribute to a control's natural width.
The app resolves these stages during layout before painting, so no
intermediate stage is ever drawn.
Long controls remain bounded by the available line.

## Views

The view order is Latest, Unread, New, Unseen, Top, and Trending. The app omits
personal views for signed-out readers and uses the forum's New and Top
configuration. Counts on several views describe their union. Unified New
overlaps Unread, while legacy New and Unread are disjoint.

On a desktop the views are a switch. The current view remains visible. Up to
three segments fit beside the overflow trigger; fitting stops at the first view
that cannot fit. The selected segment uses the raised surface and semibold
text. New and Top open their submenus. The overflow offers only the hidden
views, and its count is theirs.

On a phone the view is one quiet pill like Tags and Filters, not a switch. It
names the current view, such as Latest or New · Topics. Beside the name, on
one baseline 7 points on, it shows the view's own count when it has one. A
view without a count shows instead what waits in the other views, when that
is above zero. Pressed anywhere, it opens every view, the current one checked,
as the phone's menu sheet. Its accessible name is `View: <name>`, followed by
`, <n> topics` while the view's own count shows, as the desktop toggles say
it, or `, <n> more in other views` while that total shows. Its name stays drawn and
its insets stay 12 when the header retracts.

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

On a phone the unchosen Categories pill is its mark alone, named in its
tooltip and aloud, so the row keeps to one line. A desktop keeps the word.
Every selected category level keeps its own mark and menu. A trailing deeper
level exists only when children are available within the site's nesting limit.
It says Subcategory, or No subcategories for an exact category clause.
Shortened paths keep the selected leaf's name and reduce their ancestors and
the deeper level to marks. Retracted phone headers reduce every level to a mark.
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
An inset switch's background paints at its interpolated frame size while its
segments keep their destination layout sizes.
Their paint, hit-test, and semantics transforms share the same translation.
Interrupted transitions start from the currently drawn positions. Reduced
motion applies the destination layout immediately. The phone's view pill keeps
its size throughout.

## Focused verification

`test/topic_list_responsive_filters_test.dart` renders the production filter
components with real fonts and checks expanded/scrolled phones, narrow deep
paths, filter counts, retained editors, and accessible text scaling. It also
checks that the retracted row stands closer only with a path while the view
pill keeps its name and insets, and that Categories is its mark until chosen.
`test/topic_view_switch_test.dart` checks the pill's insets, shared baseline,
count rules, accessible names, and the sheet of every view.
Set `RESPONSIVE_FILTER_REVIEW_DIR` to export its PNG captures.
`test/d_fit_row_test.dart` checks fitting stages, fitting again from `full`
when the room or a control's width changes within one frame, nested artwork
without scale, mid-transition pointer activation, retained elements, and
motion curves.
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
