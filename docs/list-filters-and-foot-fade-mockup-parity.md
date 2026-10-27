# List filters and foot fade parity

Reference: `discourse-native-mockups` at `847614e` (branch `test-mobile-layout`),
look A. The filter row is `FitRow` and its use in the list's `PageHead` in
`App.tsx`, with `.fit-row` in `app.css` (`847614e`). The fade is the
`--head-band` foot of `.head-mask` in `app.css`, measured from `--dock-now`
(`9839846`).

## The filter row

A topic list's filters, Latest, the category path, Tags and Filters, sit
on one line at their own widths. When they do not all fit, Filters drops its
word: it shows its count, or only its glyph when no filter is set. When even
that is too wide, the row wraps with everything at its full length again,
and a pill too long for a line of its own is cut short. The notification
bell and the other actions stand beside the row, not in it.

`DFitRow` is that row. It is a layout builder that holds the mockup's three
steps (full, tight, wrapped) and the width each step needed when it was left.

| Rule | Mockup | App |
| --- | --- | --- |
| What a line measures | Each pill's `offsetWidth` plus the row's `column-gap`, not what overflows the row | `RenderDControlWrap.naturalMain`: each child's own width plus the gaps |
| Next step | Natural width over the row's `clientWidth + 1` | Natural width over the row's width, within float tolerance |
| Step back | Row as wide as the step's recorded need | The same |
| Measured afresh | `watch` (sort, category, tag, filter count) changes | Any rebuild of the row's children |
| Tight Filters | Label `count \|\| null`; `aria-label` and `title` stay "Filters" | Label is the count, or the glyph alone; semantics keep the full label, "Filters · 2" |
| Gaps | 8 across; wrapped lines 8 apart | `DSpacing.sm` across, 8 between runs |

The mockup takes each step in a `useLayoutEffect` before it paints. The app
builds and measures each step within one layout pass, so neither an
overflowing line nor a premature wrap is ever painted.

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
