# Native page headings

Use `DPageSurface.headed` for each route with a page title and page controls.
Put the title in `title`.
Put filters, menus, selectors, and actions in `controls`.
Use Native components for these controls.

The kit supplies the title style and the space around the heading.
On phones, `DPageHeaderHost(titlesInBar: true)` keeps ordinary page names in
the top bar from the first frame and leaves only controls in the page heading.
On desktop, the title hides during downward input and returns during upward
input or at the top. The controls stay visible.
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
for composite headings and specialized topic readers; graphical identities without a page name leave it null. Channels supply
their name and marker through `titleText` and `titleLeading`.
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
