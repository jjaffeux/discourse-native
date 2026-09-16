# Topic list: Card and Compact

Open `index.html` directly, or serve this folder with any static HTTP server.
No build, dependencies, external fonts, images, or network requests are needed.

- **Compact:** a table with Topic, Category, Assigned to, Replies, and Activity columns;
  about 57px per desktop row, no excerpts, tags below the title, and existing
  pinned/bookmarked/closed and unread/new indicators. Read titles are subdued.
- **Card:** a source-informed approximation of the existing outlined `DItem`
  layout, including excerpts, taxonomy, last author, reply count, and activity.
- **Settings:** a new Topic list field below Content alignment. A single-select
  outline toggle group switches Card / Compact immediately, across forum lists.
  Card remains the application default; this study starts in Compact
  to put the new design first.
- **Narrow:** category moves under the title, last-author avatars disappear,
  and titles can wrap to two lines. Replies and activity retain aligned columns.
- **Assignments:** users and groups appear in a dedicated desktop column and
  beneath the title on narrower screens. Cards use the existing plugin's
  "Assigned to" footer, with assignee, group identity, and topic/post targets.
  Unassigned table cells show a dash; cards omit the empty assignment footer.
  A `+1` control opens the sample topic to show every assignment. Examples include
  a topic with both topic and post assignments, and one assigned only on post #12.
  Search also matches assignee names.

Use the study toolbar to compare layouts, desktop/narrow widths, and light/dark
themes. Open settings from the toolbar or the app's bottom-left gear. The modal
supports Escape, outside click, and native focus trapping/restoration. Search,
category/tag filters, feed selection, sample topic previews, text size, and
appearance work locally. Preferences persist only under a mockup-specific
localStorage key. Content alignment becomes visible when the content pane is
wider than its 1120px reading lane. The GIF preference demonstrates its control
state only; this fixture has no animated media.

Direct preview parameters: `?mode=compact&theme=dark`, `?mode=card&theme=light`,
`?viewport=narrow`, and `?settings=open`. These can be combined.

## Production component mapping

The approved design is implemented in Flutter using the public Native library.
This folder retains the original HTML/CSS design artifact. The later
[inline assignment proposal](assignments/README.md) replaces the assignment
column in production; [calendar stamps](event-dates/README.md) distinguish event
dates from activity.

Component mapping:

| Surface | Existing Native component |
| --- | --- |
| Settings modal and setting rows | `DDialogContent`, `DField`, `DFieldSeparator` |
| Card / Compact choice | `DToggleGroup`, `allowEmptySelection: false` |
| Compact table composition | `DTable`, `DTableHead`, `DTableCell` |
| Current card view | Existing `TopicListRow` / `DItem` |
| Buttons, selection, author avatars | `DButton`, `DSelect`, `DAvatar` |

The production list preserves its existing SuperListView, lazy loading, scroll
restoration, keyboard navigation, and plugin metadata. Each interactive Native
Item contains an aligned Table row; the column header stays above the viewport.
The assignment `+N` action opens the topic using the list's normal navigation.
There is no eagerly built table replacing the virtualized feed.

Run the offline native review with:

```sh
flutter run -d macos --no-pub -t tool/topic_list_modes_review_main.dart
```

It mounts the real MainContent and settings modal using in-memory preferences
and fixture data. Controls switch modes, theme, a 390px pane, 200% text, and RTL.
No forum account or server data is used.

## Review

Reviewed in the Codex browser: dark desktop table/cards, light narrow table/cards,
and settings at desktop and narrow viewport sizes. Checked modal mode changes,
Escape dismissal, search, empty-state reset, unread filtering, theme changes,
and preference persistence after reload. The narrow preview had no horizontal
overflow; desktop compact rows measured 57px. JavaScript syntax validation passed
and the browser reported no warning/error logs.

Assignment update: reviewed desktop and narrow cards/tables, user and group
identities, unassigned cells, post targets, and the multiple-assignment disclosure.
The narrow list still has no horizontal overflow; no browser warnings or errors.


Native implementation review: inspected macOS debug Card and Compact lists,
the Settings modal, light/dark themes, wide and 390px panes, and 200% text in
RTL. Compared the layout with the Native Table styleguide. Verified settings
switching and assignment visibility in the running app. The final `+N` topic
navigation is covered by widget tests; the Mac locked before its final native
recheck. No iOS/Android device review was performed.

Validation used Flutter 3.47.4 / Dart 3.13.3 from the installed SDK; the project's
3.47.2 pin was left unchanged. Static analysis and focused list, settings,
assignment, plugin and Aggregate tests cover the implementation. The existing
`feed select retains keyboard focus across routes (stacked: true)` test fails
identically on the unchanged starting commit `e0463c02` and this branch.
