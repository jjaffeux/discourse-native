# Topic card parity — 2026-10-02

Reference: `discourse-native-mockups` commit `912027c`, `src/App.tsx`,
`TopicRow`, `topicPosters`, and the taxonomy sizing helpers immediately above
`TopicRow`. The screenshot supplied with the request shows this layout.

## Changes from the previous Flutter cards

| Area | Previous implementation | Updated implementation |
| --- | --- | --- |
| Row geometry | Desktop flush rows with a leading selection stripe; mobile inset rows | Both layouts use 16px horizontal margins, 12px vertical padding, and rounded accent selection at 4px margins with 12px internal padding. Text stays on its original horizontal edge. |
| Rules | Full-width desktop separators | Inset separators, omitted beside selected rows on every width. |
| Reading measure | Desktop title/excerpt occupied the available pane | Title and excerpt are limited to 760 logical pixels and use the reading font. Title can wrap naturally; excerpts use two lines at ordinary text sizes. |
| Status | Leading pin/lock/bookmark icons, sometimes accented | A subdued trailing status slot after the title measure, with priority pin, closed, bookmarked. Tooltip and accessibility label include every applicable state. |
| Unread count | Desktop and mobile badge variants; count could break away from the title | Amber compact count on all widths, kept with the final title word, or final two words for a short ending such as an emoji. Existing new-topic/reply dots remain. |
| Activity time | Beside the title | Trailing edge of the footer, with tabular digits. |
| Participants | One 22px last-poster avatar and a textual byline | Up to five 20px avatars overlapping by 7px, sized to the actual participant count. Server order, usernames, role descriptions, and latest/single flags are retained. |
| Participant outline | Online/success ring only | 1.5px surface separation and an outside accent ring for the latest poster. A sole participant has no latest-poster ring. Native defaults elsewhere remain unchanged. |
| Taxonomy | Filled/outlined tag chips, fixed five-tag limit, passive overflow badge | Plain `#tag` links, width-based fitting, middle-clipped category names, end-clipped tag stubs, and an actionable `+N` that expands the remaining tags. |
| Category hierarchy | Immediate parent only | Up to five levels, with cycle protection; levels already represented by the current category filter are omitted. |
| Counts | Textual reply count and optional views; no likes | Comment and heart icons with compact reply/like numbers, full accessible count labels and tooltips. Explicit views and desktop sort actions remain supported. |
| Muting | No card treatment | Muted topic cards use 55% opacity. |
| Loading | Generic metadata bars | Inset skeleton rows with an overlapping avatar stack, metadata, and trailing time placeholder. |

## Category and tag fitting rules

1. Reserve count widths, icon gaps, and the 14px footer gaps before allocating
   taxonomy space. Active desktop sort indicators also reserve their width.
2. The category path receives 55% of the remaining strip. If a multi-level
   path exceeds this budget, replace ancestors with `… ›` and retain the leaf.
3. Subtract swatches, chevrons, and spacing from the path budget. Give the leaf
   at least 82px where room permits, bounded by the actual available space and
   the tag-overflow reservation. Shorten the **middle** of the leaf, retaining
   both its beginning and distinguishing suffix.
4. Fit complete tags first. Reserve 16px for `+N` and 5px between tags when
   some tags remain hidden.
5. A partial next tag is allowed only when at least 30px remains after those
   reservations. Shorten its **end**. The overflow count excludes that visible
   partial tag.
6. `+N` expands the remaining tags and permits wrapping. Clipped labels retain
   full tooltips, accessible labels, and original navigation destinations.
7. Measurements use the rendered font and text scale. Clipping preserves
   Unicode graphemes. Very narrow layouts with large accessibility text wrap
   the metadata strip instead of losing links or counts.

## Native components and behavior

The user approved extending the Native components for full parity.
`DAvatar` supports an outside ring, `DAvatarGroup` supports a configurable
separation width and explicit extent for tooltip-wrapped avatars, and
`DButtonDensity.inlineMetadata` keeps 12px metadata actions within their
visible bounds on desktop and touch platforms. Examples remain in the Native
styleguide. No application-specific replacement controls were introduced.

The app uses real server likes and participant summaries, rather than the
mockup's generated sample values. Category/tag navigation, middle-click tag
navigation, desktop count sorting, keyboard selection, hover prefetch,
private-conversation labeling, forum identity, and plugin metadata are retained.

## Verification

Focused tests cover the fitting thresholds, partial-tag navigation, multi-level
paths, poster decoding and sparse updates, Native ring and hit-area geometry,
selection alignment, mobile/desktop layouts, enlarged text and RTL, sorting,
loading, accessibility-tree updates, and scrolling without retained-title churn.
Light and dark golden images cover mobile, desktop, hover, and selection states.
