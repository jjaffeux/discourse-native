# Summary page parity

Reference: `/Users/joffreyjaffeux/Code/discourse-native-mockups`, branch
`test-mobile-layout` at `5e4e72a` (`summaryView`, `SummaryBox`,
`SummaryTopics`, `SummaryTable`, `SummaryFigures` and `StatWell` in
`src/App.tsx`; `.sum-*` and `.stat-*` in `src/app.css`), checked on
2026-10-23. This supersedes the Summary row of "Latest account pages" in
`start-page-mockup-parity.md`.

| Mockup | Native |
| --- | --- |
| Head: a 28px face, the name at 22px, then `@handle`, the forum and days visited at 12px, each fact giving way whole when the line runs out | The face scales with text beside the page title. The name keeps its measured width and the facts take what is left, on one clipped line, so a fact that does not fit wraps out of sight instead of being cut. The breakpoints that showed or hid each fact are gone. Days visited carries the `calendar-days` glyph, added to `DIcons`. |
| Every block is a box: 14px corners, the subtle border, half the well's fill, its title at 14px semibold inside, 16px between boxes | `DCard` in the `well` variant, with `footerBorder` (the reference's `--border-subtle`) and half the well's darkening. Its small title sits at 14/16/4 inside. Boxes are stacked 16px apart. The Native card shadow is gone. |
| Stat well: the full well fill; four figures with the label at 12px and the value at 20px bold, split by rules; two columns at 440px or less | Same layout, with 14px vertical and 16px cell insets and `footerBorder` dividers. The value is bold and uses tabular figures. Two columns also apply at large text, as before. |
| Top topics and replies: a rule over every row, inset 16px. The title is the reading face at 14.5px medium on one line. The category square, name and age are at 12px, and the heart and count at 11.5px | Full-width `DItem` rows with 10/16 padding, so hover spans the whole box. The title is a single ellipsized line in the reading face. |
| Tables: 11.5px semibold headers. Each row has a 22px mark, the name at 13px in the reading face with a muted note on the same line, and right-aligned 12px values in fixed columns | One `_SummaryTable` drives people, categories and links through `DTable`. Its columns are fixed and scale with text: Replies/Likes 72px, Topics 64px, Posted in 200px, Clicks 56px. The rules use `footerBorder`. People show `@handle` beside the name. Categories and links are marked with the reference's tinted tile (tag and link glyphs), composed from `DAvatar` like `DPlaceCardMark`. A link's note is its domain. Posted in drops at a box width of 520px or less. |
| Time well spent: 28px bold headline, a 12px note, then figures as table lines (label 12.5px, value 13px semibold) with a rule over each | Same; the figures stack under their labels at narrow widths and large text. |
| Milestones: the Start page's 37px rows packed across the width, an accent tile and the name | Wrapped 37px rows, up to 280px each, on the footer fill with the accent tile. A repeat count follows the name, and the description stays in a tooltip. |
| Connections are three boxes stacked | The paired-section wrapper is removed; Highlights and Connections stack every box. |

Kept from Native, by design:

- Category counts stay inline buttons that open forum search. They are drawn
  in the table's value style rather than as accent links.
- A topic row shows its likes only when there are some, so its label never
  says "0 likes".
- `DTableHead` keeps the kit's 40px minimum header height; the reference's
  header is 34px.
- The kit's well depth paints its recessed top edge in Standard; the
  reference's box is flat there.

`test/user_summary_test.dart` covers the head's facts giving way, the stacked
figures, large text at 320 and 768px, and every existing navigation and
semantics contract. Its fixture user now carries `hidePresence`, as core's
current-user payload always does; without it the account menu's presence
skeleton never settles. Renders were checked with `SUMMARY_REVIEW_DIR` at
desktop and 200% text; no device run was made.
