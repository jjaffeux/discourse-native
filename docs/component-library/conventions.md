# Native page headings

Use `DPageSurface.headed` for each route with a page title and page controls.
Put the title in `title`.
Put filters, menus, selectors, and actions in `controls`.
Use Native components for these controls.
Use `secondaryControls` for a second row: the kit leaves 8 pixels between rows,
16 pixels at the sides and 2 pixels below the second row. Both rows share the
page's persistent controls and adaptive keyboard layout.

The kit supplies the title style and the space around the heading.
On phones, `DPageHeaderHost(titlesInBar: true)` keeps ordinary page names in
the top bar from the first frame and leaves only controls in the page heading.
On desktop, the title hides during downward input and returns during upward
input or at the top. The controls stay visible.
Phone topic lists use `retractControls: true` to move their filters offscreen
with the scroll while their title stays in the top bar. Their shared header
motion uses `DHeaderSettle.stay` with zero smoothing, reversal slack and hold.
`DPageHeaderScope.maybeOf(context)` exposes the owning page's `DPageHeader`
inside its heading, controls, and body. Listen to its `value` for retraction
from zero to one and call `scrollToTop()` to return only that page to its
physical top. The action honors reduced motion. Unlike header geometry,
this listenable supports widget builders and does not notify during layout.
Its `barOpacity` supplies the surrounding title visibility independently of
header retraction. Phone topics use `fadeHeaderOnScroll`: `DHeaderMorph` parts
fade as the first post approaches them, and the topic name enters the bar as
its title fades. The full header keeps one layout.
Headed pages infer `titleText` from a plain `Text` title. Supply `titleText`
for composite headings and specialized topic readers. Graphical identities
without a page name leave it null. Specialized readers supply `titleMetadata`
for the secondary identity line in surrounding chrome. It follows the title
fade and retained page transitions. Channels supply their name and marker
through `titleText` and `titleLeading`.
`DPageHeaderHost` shares the innermost foreground header with surrounding
chrome. Its identity follows the navigation entry. Native sheets exclude
their retained underlays, and inactive pages cannot publish through the host.
Do not add a divider, a background fill, or a local shadow below the controls.
The Native scroll fade supplies the soft edge when content continues above the viewport.

For a lazy viewport, use `bodyBuilder`.
Reserve `header.spacer` at the start of its scroll content.
`DPageScrollInsets` supplies this space as padding for lists that need padding.

```dart
DPageSurface.headed(
  title: Text(title),
  controls: controls,
  bodyBuilder: (context, header) => CustomScrollView(
    slivers: [
      SliverToBoxAdapter(child: header.spacer),
      ...contentSlivers,
    ],
  ),
)
```

For a bounded table or calendar, use `child`.
For a directory with a keyboard fallback, use `adaptiveBodyBuilder`.
Its boolean argument selects a bounded lazy list or content with its natural height.
The kit measures the heading before it selects the layout.
For an indexed directory, set `foldTitleAtTop: true`.
This option keeps the title hidden away from the top, including during programmatic jumps.

Use the lower-level `header` slots only for specialized topic and conversation readers.
Do not use them to create another route-heading layout.
Channel readers use one compact header from their first loading frame.
On phones, channel names stay in the bar with `holdTitleInBar: true`, while
their own header may retract. Thread readers retain their existing layouts.
Set `minimumScrollExtent: 0` on channels so the shared mobile tab bar can retract on short transcripts.
See the Page surface example in the styleguide and the route audit in [Page header parity](../page-header-mockup-parity.md).

# Sheet headers

Use `DSheetContent` for sheet surfaces and `DSheetHeader` for their top row.
Put corner actions in the header's `leading` and `trailing` slots. Use
`DSheetHeaderAction` for these actions and `DSheetHeaderAction.close` for an X.
The built-in sheet close button uses the same component. Keep the default close
button enabled unless the header supplies its own close behavior or the sheet
uses navigation or swipe dismissal alone.

The kit places bottom-sheet handles 8 logical pixels below the surface edge
and corner buttons 12 pixels from the top and side. Top system safe-area padding
belongs outside a bottom sheet. The sheet retains its bottom safe area for
content and actions. Header buttons keep their normal Native size when menu
content is enlarged, and titles can wrap without moving the buttons downward.
Reading-page sheets use the same handle. Their host owns navigation and swipe
dismissal.

See the Corner actions example in the Sheet styleguide.

For a phone identity card with content below it, use an adaptive menu sheet with
`restAt` pointing to the card's `GlobalKey` and `scrollWholeSheet: true`.
Pass the same key to `showDSheet` when using the imperative helper.
Place `DSheetSwipeHint` immediately after the card. The kit owns its 40-point
height, delayed peek, spring, fading, safe-area cut and scroll handoff.
Keep `headerImage` on `DSheetContent`: the kit scrolls it with the resting card.
Pass long content below the card as `slivers`, so its rows are built on demand
and released once they scroll away.
`DSwipeHint` shares the shimmer with the mobile dock and honors reduced motion.
