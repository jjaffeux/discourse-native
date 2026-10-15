# Native page headings

Use `DPageSurface.headed` for each route with a page title and page controls.
Put the title in `title`.
Put filters, menus, selectors, and actions in `controls`.
Use Native components for these controls.

The kit supplies the title style and the space around the heading.
It hides the title during downward scroll input.
It shows the title during upward scroll input and at the top.
The controls stay visible.
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
Set `minimumScrollExtent: 0` so the header and shared mobile tab bar can retract on short transcripts.
Thread readers keep their existing full and compact layouts and scroll policy.
See the Page surface example in the styleguide and the route audit in [Page header parity](../page-header-mockup-parity.md).
