# Users directory parity

Reference: `/Users/joffreyjaffeux/Code/discourse-native-mockups`, branch
`test-mobile-layout` at `13db54c` (`UsersView`, `ColumnMenu`, `FilterPill`
and `WordsPill` in `src/App.tsx`), checked on 2026-11-10 at 1280×800 and at
375 wide with touch.

| Mockup | Native |
| --- | --- |
| Controls: the search field at 220, then Week and All groups as quiet pills sized to their labels (at most 88 and 96), 8 apart; Columns stands outside the wrapping filters at the end of the first line, all top-aligned | `_FilterRun` in `users_page.dart` lays out the field and the pills the way the wrapping flex row does. Each pill takes its own width while it fits on the line and moves to a new line when it does not. Columns sits beside the run in a `Row`. Period and group are `DSelect` at filter size. The group filter is a plain list; it no longer filters as you type. |
| On a phone the field grows into whatever its line has left (`flex: 1 1 220px`) | The run grows the field when `DPageHeaderHost.titlesInBarOf` is true, the phone shell's signal. At 375 wide the field fills the first line beside Columns and both pills wrap to the second, aligned left. |
| Opened from search: a quiet “words” × pill leads the controls, and the title reads “words” in users | `ShellSearchController` records which Users filter came from search. The page draws the pill with the categories page's look and keeps the filter field empty. Discourse's directory takes one name filter, so typing in the field replaces the words and the pill goes away. In the mockup the two filters combine. |
| Table: a grid of 170 (User, Name, text fields) and 132 (counts) with 16 between columns and at either end, flush with the title | `DDataTableVariant.directory`. A fixed column width is the content width, and the variant adds the gaps. The table starts at the lane edge, so labels and avatars line up with the title. |
| Header: 12.5 semibold, secondary or strong when sorted, both chevrons faint until sorted, labels over counts right-aligned, 8 under the labels | `_SortHeader`. A press orders the directory: the sorted column reverses, a count starts descending and a name ascending. Name has no sort mark because Discourse cannot order the directory by name. There is no header menu and no column resizing. |
| Rows: 8 over and under a 22 avatar, a subtle hairline over each, 39 apart; handle 13.5 strong; a missing name blank; a missing text field "—" muted | Same, with `footerBorder` for the hairline. |
| Counts over a 20-tall `--surface-raised` bar with 3 corners, 13px, 2 in from the end | `DChartBar` with `raisedBackground` and `radius: 3`. Without a track it rounds both ends. |
| Columns menu: at least 200 wide, a "Columns" label, the check at the end, the last shown column locked | `DDataTableColumnToggle`: 200 wide, no separator, and the last shown column cannot be turned off. |
| "Day" … "All time"; "No users match that filter." | Same strings. |
| The title slides away as the list scrolls down and returns on a short scroll back up | The shared `DPageSurface.headed` retraction, as on Groups and Categories. The page no longer folds its title for as long as it is away from the top. |

Column widths that an earlier version saved for each forum are no longer read.
`RetiredUserDirectoryColumnWidths` keeps their key declared, so forgetting a
forum still removes them.
