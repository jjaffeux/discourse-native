# Pagination

Task `01a08606-c9d5-7741-bfe0-e4ff531ff9b7`, branch
`codex/ui-pagination`. Frozen reference date: 2026-09-08.

## Reference

The frozen Markdown hash is
`bc07e7b5e3df7090f895a93d49a3484e828e8560c17600ab3cbd1cb92313c3f9`,
exactly matching `catalogue.json`. The current official base-nova registry was
captured separately; its upstream raw hash is
`d2c45af4aaf4a676f420c673f337e8ba89dc7db75bf9fa11143f8a947f3a7f42`
and its extracted source hash is
`092fc14c783c11e10dfbd0636bc511af7c7ace4ccb95c3ef7ab9ea696694c422`.
See `reference/pagination/` for the exact sources and provenance.

Measured mapping at a 16px browser root and 100% Flutter text scale:

| Reference | Flutter mapping |
| --- | --- |
| `nav`, full width, centered | `DPagination`, labeled explicit semantics container and centered logical alignment |
| `ul`, horizontal, `gap-0.5` | `DPaginationContent`, 2 logical-pixel gaps |
| default page link `size=icon` | 32×32 `DButton` ghost surface; current page uses outline |
| `aria-current=page` | selected semantics plus localized `Page n, current page` default name |
| Previous/Next `h-8 gap-1.5` | 32px `DButton`, 6px icon gap, directional 6px outer inset and 11px label inset |
| `hidden sm:block` labels | labels hide below 640px while full spoken labels remain |
| default SVG size | custom 16×16 round-cap chevron/dots artwork; logical direction flips in RTL |
| ellipsis `size-8`, `aria-hidden` | 32×32 non-action marker, excluded from semantics by default |
| `rounded-lg` and live variables | completed `DButton` owner reads live host font, palette and proportional base radius |

The narrow native adaptation gives the centered row horizontal scrolling instead
of overflow. It does not alter compact control paint bounds or reading order.
Touch platforms retain the completed Button owner's invisible target expansion.

## API and behavior

- `DPagination`, `DPaginationContent`, `DPaginationItem`,
  `DPaginationLink`, `DPaginationPrevious`, `DPaginationNext`,
  `DPaginationFirst`, `DPaginationLast`, and `DPaginationEllipsis` expose the
  complete composition anatomy. Link callbacks own Flutter routes, browser URLs,
  and query parameters.
- `DPaginationNavigation.local` owns state, `.controlled` displays parent-owned
  state, and `.controller` borrows a `DPaginationController` without disposing it.
- Pages are one-based. Empty data keeps `page == 1` but `pageCount == 0` and
  disables every movement control. A single page likewise disables movement.
- The window always contains requested boundaries and siblings. One missing page
  is rendered directly; larger gaps produce an ellipsis. First/last controls are
  opt-in, while page numbers and direction text can be independently omitted.
- Direction controls default to the reference ghost surface. `directionVariant`
  can select outline for the official Data Table composition without duplicating
  navigation artwork or behavior.
- `DPaginationController.updateTotalItems` calculates page count and clamps the
  page. A page-size change preserves the old first visible item unless explicitly
  disabled. Notifications are coalesced per update.
- `DField` supplies only the horizontal label/layout for rows per page;
  `DSelect<int>` remains the sole value, focus, action and Form owner.

## Documented examples and acceptance

The styleguide includes Default, Simple, Icons Only with the final Field/Select
page-size composition, routing links, controller/dynamic-count edges, and the
official Arabic RTL composition. The dynamic example exercises empty, single,
clamped, and first/last states.

Independent acceptance compared the live official light and dark examples and
measured their 32px controls, 2px gaps, 10px radius, typography, logical
directional padding and current-page outline. The source-exact native macOS
fixture then exercised pointer and keyboard activation, current/disabled
semantics, page-size Select updates, caller-owned routing, dynamic clamping,
single/empty states, light/dark/Forest palettes, Arabic RTL, 216px/200% text and
reduced motion. The styleguide example is therefore promoted to implemented.

The review fixed `DPagination` cross-axis expansion inside bounded footer
layouts by shrink-wrapping its inner alignment, with a 240×568, 200%-text
regression. It also corrected the local review fixture so its 216px control
changes `MediaQuery` and genuinely enters the sub-640px responsive branch.

The inspected macOS review bundle was built from reviewer commit `eb2fe331`.
Its fixture hash is
`9f6812dcbb4dce9ed6a6db93f00a06d5492fd3305b3729403896f7c14ecadd0f`,
and the build and copied bundle kernel hashes both equal
`5af1cf6aceafa49a34c923a0a351e5b8f4e08ed37c9f73f25010366dcea19d39`.
The isolated ad-hoc identity was
`org.discourse.pagination.review.eb2fe331`; signing verification passed without
an application/team identity. The harness-only responsive correction was then
rebuilt from `6a3fbe6a`: fixture hash
`7edba68232f0e62a6818943eed2d2cd922569e66013a0f21f795188732b42865`
and build/copied kernel hash
`3ae4143ca55457e0701e1882a81a6adfefde3319b29d06ee82d9f417d4402ead`.
That replacement bundle was signature-verified but could not be relaunched after
the Mac auto-locked; the actual sub-640 branch is covered by the widget suite.

## Application audit

The current core and bundled-plugin paging surfaces are cursor, offset-append,
or scroll-position flows rather than bounded replace-one-page lists:

- Topic, category, aggregate, search, account activity, drafts, users, groups,
  invites, badges and assignments append server pages or preserve virtual scroll.
- Chat browse, search, channel threads, member lists and GIF search likewise use
  cursor/offset continuation and expose Load more or automatic end loading.
- Topic post navigation and Carousel/Lightbox `PageView` are position navigation,
  not result-set pagination.

Replacing any of these with numbered bounded navigation would discard accumulated
results or change reading flow, so they are deliberately retained. No production
consumer is migrated in this task. Data Table is the first appropriate bounded
consumer and is preparing directly against this public API in task
`01a08606-ca45-73b1-9be1-7486d4e3fe1d`; its server/manual paging adapters remain
outside the generic component.

## Dependency gates

Button is accepted on main. Field is accepted at merge
`5cd7f3694498e4e09e3c114639baca834b56705e` with metadata follow-up
`1001ed005ade4aec0d5f5346473054fb976d2260`. Pagination integrated the accepted
Field source without merging newer main into its worktree.

Select source preparation uses exact reviewer commit
`7d474deffdb0cdda5f13f83ceaf1b4bfff6a6581` from `codex/review-select`, task
`01a085e1-1106-7ba1-a30c-15a8a7a5bd22`. The accepted Select landed at merge
`57bbeb94368649a4665483180e4f5c84b5f33856` with metadata follow-up
`94a65e00c525d6096f12be94fcc2ec9bbaf888ff`; Pagination's reviewer confirmed
its Select/Popover bytes match and will reconcile the final Pagination candidate
from current main before merging.

The native acceptance was limited to macOS. No iOS/Linux device or spoken
VoiceOver pass was performed, and no authenticated production surface was
opened; the application audit found no appropriate existing bounded-page
consumer. The corrected review-harness bundle was not reopened after the host
locked; this limitation applies only to the fixture toggle, not to the unchanged
Pagination implementation already inspected natively.
