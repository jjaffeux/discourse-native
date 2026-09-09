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

Acceptance requires keyboard and pointer activation, disabled/current native
semantics, borrowed lifecycle, live light/dark/custom themes, 216px/200% text,
RTL and reduced motion. The independent reviewer must perform the first actual
official browser comparison and native macOS inspection before promoting the
example from baseline.

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
`01a085e1-1106-7ba1-a30c-15a8a7a5bd22`. Its focused and downstream checks passed,
but this is not acceptance. Pagination's reviewer must start its final candidate
from current main, wait for accepted Select, reconcile the final owner revision,
rerun affected Field/Select/Pagination checks, and prevent unaccepted Select
ancestry from reaching main.
