# Start page redesign parity

Reference: `/Users/joffreyjaffeux/Code/discourse-native-mockups/src/App.tsx`
(`homeViewFor`, `HomeScroller`, `HomeColumns`, `HomeSection`, `HomeCards`,
`HomeCard`, `BarOverflow`, `ForumSwitcher`) and `src/app.css`.
The live reference was inspected at mobile width and in a narrow desktop panel.

| Area | Previous app | Redesigned mockup / implementation target |
| --- | --- | --- |
| Layout choice | Comfortable cards and compact rows, with a saved density toggle | One row layout on every platform; remove the toggle and ignore the old preference |
| Forum heading | 46px logo and title above the website | Mobile: a static 28px logo only. Desktop: 28px logo, 22px title, menu chevron, and muted website on one line |
| Forum title action | Passive title | Desktop: Native menu with Open forum in browser and Remove forum. Mobile: no title button or menu |
| Header actions | Filters beside title and density | Filters and navigation shortcuts on their own bar below the title |
| Filters action | Large icon-only filter trigger | Compact Native button with the Filters label |
| Header button styling | Filled shortcuts beside outlined Filters and More | One raised chip treatment for Filters, shortcuts, and More: 10% foreground fill, Native 1px palette border, matching radius and height |
| Shortcut location | Everything else section at the foot | Header bar; no Everything else section |
| Shortcut overflow | All shortcuts wrap in the body | Keep fitting shortcuts in order, then a More menu containing the remainder; measure actual Native buttons |
| Shortcut order | Bookmarks, Latest topics, Categories, Chat, other pages | Empty Bookmarks, Categories, Chat, Recent topics, then Messages, Groups, Badges, Upcoming events, Users, Preferences, Settings |
| Sections | Headings over unframed row groups | Borderless rounded wells, 6px inset, darker fill from the active palette |
| Well color | No shared section fill | Preserve hue/chroma and subtract 0.08 Oklch lightness on both light and dark palettes |
| Section links | Label-sized action, chevron beside title | Whole visible heading row opens the section, with the chevron at the far edge |
| Section heights | Each section ends after its own rows | All wells in a grid row have equal height, keeping shorter contents at the top |
| Grid columns | Maximum fitting columns, including uneven 3+1 layouts | Prefer a fitting column count that divides the section count evenly, without reducing prime counts to one |
| Grid gaps | 18px columns / 28px rows | 18px in both directions, plus 18px from the header bar to body |
| Categories | First catalogue entries regardless of visits | Up to four recently visited, still permission-filtered against the current catalogue |
| Chat | Followed conversations ordered by unread/activity | Up to four recently visited conversations in visit order, retaining live unread metadata and avatars |
| Topics | Fetch Latest on entry; label Latest topics | Up to four recently visited topics; label Recent topics; read cached data without a request |
| Bookmarks | Up to four rows, or a separate comfortable layout | Up to four cached bookmark rows with reminder/Due metadata |
| Closed tabs | Chips or comfortable previews | One full-width well with naturally sized chips, capped at 280px; preserve restoration, context menus, and desktop drag |
| Row appearance | Different card and row paths | One Native row path with footer fill, one-line reading-font title, tinted type/category mark, and trailing metadata; unread and Due badges use the accent |
| Empty sections | Body shortcuts | Header shortcuts remain available without loading every directory |
| Search on Start | Server search popup | Desktop chrome field filters cached Start contents in place and shows result / no-match text; queries belong to their tabs and matches are selected before trimming bookmark previews |
| Header scrolling | Entire page header scrolls with the body | Retract the title on deliberate scroll while keeping the control bar visible |
| First visit | Panel tutorial ahead of sections | Same launcher surface as subsequent visits; no tutorial card |

The mobile logo-only Start heading follows the requested mobile treatment;
the mockup's shared named heading remains the desktop reference.

The reference declares Drafts, Messages, Groups, Badges, Upcoming events, and
Users preview renderers, but its active `homeFull` selection contains only
Bookmarks, Categories, Chat, and Recent topics. Its arrangement helpers are
not connected to any rendered controls. These unused renderers and helpers
are not additional visible sections or interactions. The app continues to
respect authentication and installed-plugin availability for destinations.
The mockup's seeded sample histories are not production data: a new account
has shortcuts until it actually visits destinations.

The mockup's `BarOverflow` does render a labelled More button when header
shortcuts do not fit. It disappears when all shortcuts fit and restores them
in place as the panel widens. Filters, shortcuts, and More all use `toolChip`;
their Native equivalents retain the same raised fill and thin palette border.
The header parity regression checks the rendered fill, border, radius, height,
and hover state in light/dark palettes across a wide/narrow/wide resize.

Validation: all 103 focused tests pass across the Start page, page surface,
search controllers/presentation/accessibility, and filter lifecycle. Targeted
analysis reports no issues. Real-font renders were inspected on desktop and
phone in light/dark themes and at 200% text. Tests cover balanced/equal-height
wells, title retraction without scroll jumps, shortcut overflow, local filtering
and tab isolation, forum actions, permission-filtered history, context menus,
touch activation, dragging, closed-tab gaps, and restoration. Mobile retains
the existing functional Native full-screen search; the reference's mobile
search icon has no handler. Native component sizes, text scaling, keyboard
behavior, context menus, and hit bounds remain owned by the UI kit.

The final merged-main check passed 114 tests. Two recently added global-search
presentation cases failed identically on unchanged main (`b4924e909`):
“All results and dedicated scopes use the live query and keep conditions” and
“Result dismissal clears filters from every search scope”. Both expect a chat
search result absent from that baseline. These are existing failures; merged
Start-page tests and targeted analysis remain clean.
