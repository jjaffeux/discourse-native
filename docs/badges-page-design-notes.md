# Badges page design study

Open `badges-layouts.html` to compare three interactive HTML/CSS proposals. The
preview controls switch layout, theme, language, and desktop/phone width. Clicking
a badge opens its details; the split layout keeps details beside the list on wide
screens and navigates to them on narrow screens.

The HTML previews use sample data. The native app implements option A, grouped
cards, with live forum data. Open **More → Badges** to browse them. Badge links and
notifications open native details, including paginated recipients, award dates,
and visible awarded posts. Recipient filters and badge tabs survive restoration.

The native page uses the existing reading lane, site theme, typography, HTML
renderer, and image transport. Disabled forums hide the destination; loading,
empty, retry, and anonymous states are supported. Title eligibility is shown as
metadata; changing a profile title remains outside this implementation.

## Alternatives

| Option | Presentation | Tradeoff |
| --- | --- | --- |
| A — Grouped cards | Responsive cards with a small badge icon, description, award count, tier, and earned check | Recommended starting point: follows core's catalog and the native Groups page; uses more vertical space than rows |
| B — Compact rows | Full-width grouped rows, descriptions under names, counts and tiers aligned on the right | Fast to scan and handles long text well; less emphasis on each badge |
| C — Browse & inspect | Compact grouped list with an adjacent detail pane; stacked navigation on narrow screens | Keeps context while exploring badges; needs selection state and more width |

All three show the same sample records in the same order. Counts and earned states
for the six Initiation badges come from the supplied screenshot. Other counts and
earned states are illustrative. Longer explanations and some translated labels
are shortened or paraphrased for the study. This is a representative subset, not
a complete list of core badges. Icons use Lucide equivalents in the HTML preview;
the native implementation should resolve the server-provided icon through DIcons
or display the server-provided badge image.

## Existing app styling

- `lib/src/theme/app_theme.dart`: the light/dark ShellColors palettes, blue
  selection state, muted metadata, and success color. Actual site palettes should
  remain the authority when a forum supplies one.
- `lib/src/theme/discourse_typography.dart`: 16px base text; approximately 14px
  descriptions, 12px metadata, 18px section headings, and 24px detail headings.
- `lib/src/shell/adaptive_shell.dart`: 48px site rail and 208px default sidebar.
- `lib/src/shell/forum_tabs_bar.dart` and `shell_metrics.dart`: 38px forum tabs and
  52px content header.
- `lib/src/shell/groups_page.dart`: 12px grid spacing, 16px card padding, and
  responsive column changes around 620px and 980px of content width.
- `lib/src/models/site_appearance.dart`: the 4px default border radius.

## Core reference and implementation contract

Reference checkout: `/Users/joffreyjaffeux/Code/pr-discourse`.

| Source | Behavior to preserve |
| --- | --- |
| `frontend/discourse/app/routes/badges/index.js` | Loads listable badges, reusing preloaded data when available |
| `frontend/discourse/app/data/builders/badges.js` | Requests `/badges.json?only_listable=true` |
| `app/controllers/badges_controller.rb` | Requires `enable_badges`; `only_listable=true` filters enabled/listable badges even for staff |
| `app/serializers/badge_index_serializer.rb` | Includes badge grouping and signed-in user's `has_badge`; anonymous responses omit earned state |
| `app/serializers/badge_serializer.rb` | Supplies names, descriptions, long descriptions, grant counts, type, icon/image, slug, title eligibility, and multiple-grant flags |
| `frontend/discourse/app/controllers/badges/index.js` | Orders by grouping position, then bronze/silver/gold, then localized badge name |
| `frontend/discourse/app/models/badge-grouping.js` | Translates system grouping names; falls back to the supplied name for custom groups |
| `frontend/discourse/app/templates/badges/index.gjs` | Renders each grouping with a heading and its badges |
| `frontend/discourse/app/ui-kit/d-badge-card.gjs` | Supports icons and images, sanitizes description HTML, displays nonzero award counts, and exposes earned status accessibly |
| `app/assets/stylesheets/common/base/user-badges.scss` | Core card geometry and bronze/silver/gold icon colors |
| `frontend/discourse/app/routes/badges/show.js` and `templates/badges/show.gjs` | Badge detail, recipients, grant dates and associated posts; title selection and repeat-award information when applicable |

The native implementation should preserve description links using the app's HTML
rendering/link routing, support custom badge images and groupings, respect the
forum's badge setting, and handle loading, empty, failure, and anonymous states.
Badge counts mean awards, not necessarily unique recipients, because some badges
can be granted repeatedly. Do not infer completion progress from `grant_count` or
`has_badge`. The prototypes add a small derived earned total and explicit tier
labels; those are design suggestions, not existing core index controls.

The native detail requests `/badges/:id.json` and
`/user_badges.json?badge_id=:id&offset=:offset`, preserving the optional `username`
filter used by core notifications. Pagination follows the server's 96-award page
size and deduplicates by grant ID, so repeat awards to one person remain visible.
Account lifecycle leases prevent stale requests from restoring another session's
earned status or recipients. The HTML preview demonstrates metadata and
navigation only.
