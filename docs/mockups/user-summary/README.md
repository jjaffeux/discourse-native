# User summary design proposals

Open [index.html](index.html) to compare three responsive, interactive HTML/CSS
directions. Each direction also opens independently:

1. [The overview](overview.html): four headline metrics, contribution tabs,
   community alongside content, and secondary statistics in a disclosure.
2. [The contributions](contributions.html): an editorial layout led by the
   most liked topic, with other topics, replies and links in a reading column.
3. [The profile](profile.html): a persistent identity column and Highlights,
   Connections and Reading tabs.

Selected direction: **03, The profile**. Implemented in
`lib/src/shell/user_summary.dart` using the Native kit. The profile prototype
also reflects the requested copy removals. See [the implementation record](implementation.md).

The HTML files remain design studies. The Flutter implementation uses the real
kit components and current forum theme; it introduces no dependencies or shared
kit changes.

## Current page inspected

- `lib/src/shell/user_summary.dart`: the actual page, responsive pairs, ten stat
  values, topic/reply/link/user rows, category search and badges.
- `lib/src/models/user_summary.dart` and `discourse_user.dart`: available data
  and visibility rules; top lists are capped at six results.
- `docs/component-library/evidence/button/native-v8-summary.jpg`: saved native
  screenshot showing the current summary layout with sparse sample content.
- Component conventions, frozen catalogue, styleguide design, progress and
  inventory; actual Card, Tabs, Item, Avatar and Chart styleguide examples;
  component source, typography, control foundation and AppTheme mappings.

The starting page gives ten tiles similar prominence, uses uppercase section
headings and repeats the same two-column treatment for unrelated lists. Sparse
accounts get many individual empty messages. The proposals use a clear identity
header, differentiated hierarchy, deliberate grouping and one useful empty
panel per visible section.

## Native kit implementation map

Application callers use
`package:discourse_native/discourse_ui.dart`.

| Proposal element | Existing owner / composition |
| --- | --- |
| Surfaces | DCard, DCardHeader, DCardTitle, DCardDescription, DCardContent, DCardFooter |
| Metrics and headings | DText with DiscourseTypography sizes, DSeparator, ordinary layout inside DCard |
| Secondary statistics | DCollapsible, DCollapsibleTrigger, DCollapsibleContent |
| Topic and link rows | DItemGroup, DItem, DItemContent, DItemTitle, DItemDescription, DItemActions |
| People | DItemMedia with DAvatar; keep the app's AvatarImage and UserCardTarget adapters |
| Content switching | DTabs, DTabList (line/default), DTabTrigger, DTabPanel |
| Actions | DButton outline/primary/ghost, regular DControlSize (28px) |
| Category counts | DTable, DButton; existing CategoryIcon and category search callbacks |
| Badges | DBadge with the existing badge data |
| Empty, loading, error | DEmpty parts, DSkeleton, DAlert and DButton |
| Preview inspection | DDialog in HTML study; production retains existing topic/user/search navigation |

No new generic component is necessary. A reusable stat or section composition
can remain in the summary's application adapter, composed from these owners.
DItem already exposes a padding option for compositions. The user's permission
to add kit components need not be exercised for these designs.

The HTML classes are a visual translation of the kit, not an alternative
production component library or a claim that Flutter widgets execute in HTML.
Row spacing and page layout vary intentionally between directions. Card radius
uses the saved 4px forum radius × 1.4; button geometry uses the current shared
8px radius and 24/28/32px sizing convention. Typography uses the system font and
the existing 12/14/16/18/20/24/30/36px scale. On coarse pointers the HTML study
expands controls to 48px; production should retain the kit's separate native hit
targets and text-scaling behavior.

## Data and appearance

All names, counts and content are fictional and shared between proposals.
Category topic/reply totals match the sample global totals. The designs retain
every existing summary category: topics, replies, links, three people lists,
categories, badges and all ten statistics. “Recent reading” means the existing
last-60-days field. No trend graph, growth percentage, arbitrary date filtering,
reading streak or inferred engagement score requires a new API.

`palette.css` derives its swatches from the existing
`../button-directions/palette.json` appearance snapshot. It uses semantic roles,
the accepted contextual control tints and theme-derived borders. Small secondary
text uses the palette's `primaryHigh` role for readability. This is a design
preview, not a pixel-exact render of AppTheme. The sample community name is
Discourse Meta; the deliberately fixed dev palette allows fair comparison.

The comparison includes populated, new-member, stats-unavailable, cached-refresh
error and loading states. Stats-unavailable follows `canSeeSummaryStats` by
removing account totals while retaining contribution lists. In production also
retain badge enablement, conditional bookmarks/recent-time display, individual
empty sections, partial responses, account lifecycle ownership, pull-to-refresh
and all existing route behavior.

## Interaction

- Switch designs, palette, width (desktop, 768, 390, 320) and sample state.
- Switch content and people tabs with pointer or Left/Right/Home/End.
- Expand secondary stats in the overview.
- Inspect topics, links, people, category counts and badges in a local dialog;
  close with its button, Escape or backdrop. Native dialog focus returns to the
  invoking action. No external content is opened.
- “Try again” replaces the preview error with the populated local state.
- “Open full size” preserves the selected palette and sample state.

No network libraries, fonts, analytics, authentication, build step or account
requests are used. Open `index.html` directly, or serve the folder locally:

```sh
python3 -m http.server 8769 --bind 127.0.0.1 --directory docs/mockups/user-summary
```

## HTML proposal verification — 13 September 2026

- Reviewed all three desktop layouts in the Codex browser. Reviewed the overview
  and contributions in light, and profile and contributions in dark.
- Visually reviewed all three at a 320px browser viewport. Corrected the
  profile grid's minimum sizing and shortened its Reading tab. All three then
  had no horizontal page overflow (305px document width inside a 320px viewport
  with the vertical scrollbar). Profile tabs fit without horizontal scrolling.
- At 768px, all three new-member states show exactly one visible empty panel and
  no populated account totals. All three stats-unavailable states hide account
  totals and retain available contributions, with no page overflow.
- Verified contribution and community tabs, stats disclosure, a topic dialog,
  Escape dismissal, profile Reading content, Home/End keyboard selection,
  refresh-error recovery and the announced loading state.
- Checked JavaScript syntax with `node --check` and patch whitespace with
  `git diff --check`. Final comparison controls were exercised in the browser.

This section records browser verification of the HTML/CSS proposals. Flutter
checks and native inspection are recorded separately in [implementation.md](implementation.md).
