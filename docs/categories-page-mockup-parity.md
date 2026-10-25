> Historical design and capture notes. The app now uses the [flat appearance](material-mockup-parity.md); earlier glass and depth measurements describe the retired rendering.

# Categories page parity

Reference: `/Users/joffreyjaffeux/Code/discourse-native-mockups`, snapshot
`3700183`, reviewed on 2026-10-15. The categories view uses `PLACE_GRID`,
`HomeCard` with `oneLine`/`well`, `HomeTile`, `HomeCount`, and `CategoryPath`.
The final `.home-box-place` CSS overrides the older recessed well: these are
solid raised cards with a top highlight and two shadows in both materials.

| Reference | Native implementation |
| --- | --- |
| Auto-fill grid, 236px minimum width, 10px gaps | Shared Native `DPlaceCardGrid`, lazy rows, equal row heights and aligned footers without intrinsic layout. The existing reading-width preference is retained. Text enlargement reduces the column count. |
| Destination card, 100px minimum height, 12px corners, 11px/12px insets | Shared `DPlaceCard` owns the artwork, visible rounded hit bounds, one keyboard/semantic action, hover lift, shadows, selection and focus. `DPlaceCardMark` supplies the 29px tinted tile. Site-configured icons, emoji, or squares remain authoritative. |
| Single-line name, two-line blurb, corner unread pill, quiet footer | Category descriptions are decoded and search-highlighted; unread cards emphasize their name and blurb. The footer shows the topic total and available latest activity, with no featured-topic link. Private and muted states remain explicit. Production totals/unread tracking retain the existing accessible-descendant aggregation. |
| Scope picker beside a joined category path | Existing Native Select and category-path components show the server-listed roots, then only the selected category's immediate children. Search spans the accessible directory hierarchy. Filters remain in the retracting page header and wrap on narrow screens at large text sizes. |
| Clearable search pill in the controls | The category header owns the words pill; clearing it restores the selected level without leaving the page. The shell no longer adds a second pill above this page. |
| Category feed navigation and route menu | Existing category routes, Back, and link context menus are retained. Inline subcategory buttons and featured-topic actions are removed. |
| Empty, loading, failure and paged data | Loading uses the same Native card grid as the directory; retry, live unread updates, lazy paging, scroll preservation and mobile bottom clearance are retained. |

Focused widget tests cover the Native component, real category fixtures, route
navigation, path levels, search clearing, unread/muted/private categories,
paging, shell heading ownership, and inert gaps/corners. Font-loaded renders
are inspected on phone and desktop sizes in light/dark themes, Standard and
Liquid Glass, plus 200% text, RTL and reduced motion. Render exports are opt-in
with `CATEGORIES_EXPORT_DIR`. These are Flutter widget renders, not a physical
device deployment.
