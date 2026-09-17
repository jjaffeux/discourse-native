# Topics table study

Open `index.html` directly, or serve this directory with a static HTTP server.
The entire mockup is one HTML file, including CSS, icons, sample content and
interaction code. It has no dependencies or external requests.

The design follows the supplied **Screenshot 2026-09-17 at 11.04.42.png**:
a near-black continuous panel, a quiet title bar, a filled feed pill, circular
utility actions, restrained column headings, generous title space, and a rounded
surface for the active row. The reference's project metadata translates to
Category, Last reply, Replies and Activity. Last-poster identity gets a separate
column on wide screens. Assignment details remain inline beneath the title.

Every topic list fills its available pane, with **no 825px width limit** and no
fixed maximum width. This applies to all feeds, categories and subcategories,
personal messages, group inboxes, aggregate lists, assigned groups and signed-out
lists, in both Compact and Card. Headers, filters, rows, footers and list states
use the same full width. The 390px preview simulates a narrow available pane.

The title is plain, with filter, display and preview buttons aligned right on the
same top row. Feed and taxonomy selectors sit on the row below. Profile and sign-in controls belong to the app’s higher-level
bar. New topic and recent drafts sit at the bottom left, followed
by category notifications. Up/down icon buttons at the right open the previous or
next topic in the current list. Search and refresh remain in the app’s top-level
bar. The footer has no topic count or navigation caption.
The preview strip beneath the panel is a study tool, outside the application UI.

## Try it

- The **Latest** pill exposes Latest, Unread, New, Unseen, Top and Trending.
  Unread **4** and New **6** show conditional topic-count badges in the menu and
  selected pill; zero/unknown counts are omitted. Count badges align with the menu’s right edge; a selected counted feed
  places its checkmark before the badge, without reserving trailing space. The menu has no “Topic feeds” heading.
- **New** exposes All / Topics / Replies. **Top** is a group in the main feed
  dropdown with Year, Quarter, Month, Week, Today and All time indented beneath
  it, followed by Trending. Choosing a period selects Top immediately; the trigger
  reads, for example, **Top · Week**. There is no second period dropdown or row.
- Category, dependent subcategory, multiple tags and advanced filters combine. Row taxonomy
  links apply the same filters. Tag search and overflow disclosure work.
- The funnel opens filter autocomplete using sample data: begin with `cat`,
  `tag:`, `assigned:` or `status:`. Category suggestions include colored parent /
  subcategory paths; tag counts align right; assignments include people and groups.
  Arrow keys select, Enter / Tab completes, and Escape dismisses suggestions before
  closing the menu. Apply filter changes the current list without navigation.
  `tag:interface+feedback` combines tags, commas accept any matching tag, `-tag:`
  excludes tags, and prior clauses survive completion. Quoted free text and
  `created-after:` sample dates are supported. The app’s global search stays in
  its top-level bar. This HTML simulation does not execute the Flutter component.
- The sliders expose Compact / Card, excerpts, larger text, and reader placement.
  This menu is the only layout selector; the prototype’s Preferences dialog no
  longer duplicates the Compact / Card choice.
- Open a topic or its assignment **+N** to see the retained source list and
  assignment targets. Use the footer arrows to navigate that filtered list.
- In Unread, **Finish reading sample** demonstrates removal of a read topic and
  navigation to the next remaining topic. This is a prototype-only reader control.
- Event dates open a schedule with explicit start, end, year and timezone.
- The creation dropdown exposes four recent drafts, their different types,
  remaining draft count and All drafts. Draft saving is local to the current page.
- In **Group assignments**, click **Replies**, **Views** or **Activity** to sort.
  Click again to reverse, then again to restore the default order.
- The bottom preview strip switches contexts and data states, light / dark,
  and a 390px pane. **Feature map** documents coverage inside the artifact.
- Keyboard: arrows or J / K select, Enter / O open, Home / End jump, G then J / K
  open adjacent topics. Escape closes overlays or returns from the reader.
- Scrolling to the end loads the remaining fixtures. Touch pull-to-refresh is
  represented; refreshing and retries simulate completion locally.

Example URLs:

```text
/?menu=feed
/?scene=category
/?width=narrow&theme=light
/?state=incoming
/?state=page-error
/?scene=messages
/?scene=group
/?scene=aggregate
/?scene=assigned
/?scene=guest
```

## Feature inventory and source anchors

Production Dart files were treated as the authority where older design documents
describe different navigation or assignment layouts.

| Surface | Preserved in the study | Production source |
| --- | --- | --- |
| List heading | Plain topic/category title, parent breadcrumb, category details, plugin context; account controls stay in the app bar | `lib/src/shell/main_content.dart` |
| Feeds | Latest, Unread, New, Unseen, Top, Trending; signed-in gates | `lib/src/shell/topic_list_navigation.dart` |
| Feed refinements | Unified New scopes/counts; All time, Year, Quarter, Month, Week, Today | `lib/src/models/content_route.dart`, `topic_list_navigation.dart` |
| Taxonomy filters | Parent category, dependent subcategory, All options, multiple searchable tags | `lib/src/shell/topic_list_filter_bar.dart` |
| Search/filter input | Search belongs to the app bar; list keeps advanced query entry combined with taxonomy/feed, clear/reset | `lib/src/shell/topic_filter_input.dart`, `lib/src/models/content_route.dart` |
| Topic rows | Topic title, read/unread styling, unread counts, new-topic/new-reply markers, closed/pinned/bookmarked states | `lib/src/shell/compact_topic_list.dart`, `topic_list_view.dart`, `topic_list_indicators.dart` |
| Row metadata | Parent/child category links, two tags plus overflow, excerpt, last author, replies, relative activity | `lib/src/shell/compact_topic_list.dart`, `topic_list_view.dart` |
| Assignments | Optional person/group, full name, topic/post target, extra-assignment disclosure, long-name wrapping | `lib/src/plugins/assign/assignment_topic_list.dart` |
| Events | Calendar stamp, event schedule label, timed/all-day/range, full schedule and timezone | `lib/src/plugins/discourse_events/event_topic_title.dart` |
| Creation/drafts | New topic, four recent drafts, all drafts, remaining count, topic/reply/message/voice draft identities | `lib/src/shell/topic_create_button.dart` |
| Footer | New topic/recent drafts at left, category notification levels, up/down previous/next topic buttons, fallback after unread removal | `lib/src/shell/main_content.dart`, `topic_list_bottom_bar.dart` |
| Message lists | Personal/group inbox, Inbox/Unread/Sent/Archive, group Sent gate, New message, no category column | `lib/src/shell/message_inbox_title.dart`, `message_inbox_page.dart`, `message_create_button.dart` |
| Aggregate lists | Forum identity, included forums, per-forum filter input; refresh remains in app bar | `lib/src/shell/aggregate_view.dart` |
| Assigned groups | Everyone/person/group selection, app-bar search, sortable Replies/Views/Activity headers, ascending/descending/default | `lib/src/plugins/assign/assigned_group_view.dart` |
| Data states | Initial skeleton, empty, caught up, no results, initial failure/retry, refresh failure retaining rows, incoming topics, loading more, page failure/retry, end | `lib/src/shell/topic_list_view.dart` |
| Navigation/display | Compact/Card, responsive metadata, list retained beside reader, keyboard cursor, independent scroll restoration, pull-to-refresh | `lib/src/shell/topic_list_view.dart`, `main_content.dart`, `lib/src/app_shortcuts.dart` |

## Accepted implementation decisions — 2026-09-17 revision

- **All topic-list types must use the full available pane width.** Do not apply
  the 825px reading-lane limit or another fixed maximum to any topic list,
  including messages, group inboxes, aggregate and assigned lists. This covers
  Compact and Card, headers, filters, rows, footer and loading / empty / error
  states. In Flutter, ensure list containers do not inherit the constraint from
  `lib/src/shell/content_reading_lane.dart`, including wrappers in
  `main_content.dart` and `topic_list_view.dart`.

- Remove the topic-heading dropdown and profile/sign-in controls. Account controls
  remain in the app’s higher-level bar.
- Align the filter, display and topic-preview utility buttons to the right of the
  top title row; keep feed and taxonomy selectors below.
- Remove the generic leading discussion/message icon and its redundant color/dot
  states. Keep event date stamps when available; ordinary rows start directly
  with title/status icons. New/unread indicators remain after the title.
- In Aggregate, align Forum filters at the right of the feed/category/tag row.
- In Group assignments, keep the assignee filter at the right of that same row.
  Remove the ordering dropdown and direction button. Sort through clickable
  Replies, Views and Activity column headings, only where the source supports
  sorting. Replies maps to the existing posts sort. Include a Views column here.
  Header clicks cycle descending, ascending, then default order; show the active
  direction with an arrow. Keep sortable headers in Card and narrow layouts.
  Activity descending means newest first. Unsortable headings remain plain text.
- Keep creation and recent drafts at the bottom left of the list footer.
- Keep search and refresh in the app’s existing top-level bar.
- Remove the dedicated **Filter** destination / page and its built-in sidebar
  link when implementing this topic-list design. The funnel menu is the filter
  entry point and applies queries within the current list context.
- **Reuse the existing autocomplete implementation**, `TopicFilterInput`,
  `TopicFilterController` and `TopicFilterSuggestions`. Supply the same per-site
  `feed.filterOptions` (`filter_option_info`), category cache and
  `ShellController.searchFilter*` lookups. Preserve aliases, supported prefixes,
  delimiters, quoted clauses, dates/numbers, tag groups, people/groups, debouncing,
  stale-response protection and keyboard completion. Do not create a second
  production parser or a hardcoded suggestion list. The HTML only supplies local
  fixtures to demonstrate the interaction.
- Decouple filter submission from the current `destinationId == 'filter'` guard
  in `ShellController.submitTopicFilter`; bind the existing input to the active
  list's query instead. Keep site, feed, category/tags, message/group or assignment
  scope, and the current reader. Query state must survive reopening the menu.
  Aggregate lookups and queries remain scoped to each forum.
- Migrate restored legacy Filter destinations to the corresponding site's topic
  list with their query intact; retain the server filtering endpoint and existing
  filtered-list route machinery. Removing the navigation page must not discard
  saved queries or break old filter links. Update route/sidebar and input lifecycle
  coverage along with that Flutter change.
- Use icon-only previous/next **topic** controls; navigate the current source list.
  These controls never navigate browser or app history.
- Omit the footer’s loaded-topic count and previous/next caption.
- Keep Compact / Card in the list’s Display menu. **During Flutter implementation,
  remove the duplicate Topic list Compact / Card field from global settings.**
  Preserve the existing stored choice; this is a change to where it is edited.
- Put all Top periods directly under a non-interactive Top group label in the
  main feed dropdown. Each period is a direct choice with its own selected
  checkmark. Show the period in the trigger and remove the separate Top-period
  control/refinement row. Keep category/tag filters and the open reader intact.
- Feed counts come from the existing tracking model in production. Render badges
  only when available and positive. The sample shows four unread topics and six
  topics with new activity, updating when a sample is read.

## Native component mapping

This is the requested HTML/CSS design artifact. A Flutter implementation must use
the public `package:discourse_native/discourse_ui.dart` library and the current
component conventions, catalogue and styleguide. The study does not change the
application or extend the UI kit. Reference-specific control geometry is a design
proposal; production controls must use supported Native variants and size presets.
Discuss any missing kit capability before implementing it.

| Composition | Native owners |
| --- | --- |
| Row interaction and aligned columns | `DItem`, `DTable`, `DTableHead`, `DTableCell` |
| Combined feed and Top-period selection | `DDropdownMenu`, grouped period items |
| New activity segments / display mode | `DTabs`, `DToggleGroup` |
| Category and tag selection | Existing topic taxonomy adapters, `DCombobox` / `DSelect` |
| Actions / tooltips | `DButton`, `DButton.iconOnly`, `DTooltip` |
| Tracking / identity | Existing `TopicStateDot`, `TopicUnreadBadge`, `DAvatar` |
| Calendar stamp / schedule | Existing event title adapter, `DCard`, `DDialog` |
| Category path / tags | Existing taxonomy adapters, `DBreadcrumbLink`, `DBadge` |
| Search / query entry | Existing `TopicFilterInput` + `TopicFilterController` / `TopicFilterSuggestions`, composed with Native input and overlay controls |
| Loading / errors | `DSkeleton`, `DSpinner`, `DAlert` |
| Split reader / refresh | Existing resizable-pane adapter, `DResizableHandle`, `DPullToRefresh` |

## Prototype boundaries

All data is illustrative. No account actions, notification changes, drafts or
messages reach a forum. Display choices reset on reload except the context,
preview state, theme and width encoded in the URL. The simulated reader exists
to review list selection, assignments, event schedules and adjacent navigation.

The prototype models the visible controls and state transitions. Flutter's
virtualized feed, server pagination/search, full server-provided query grammar,
serializer/plugin permission gates, session ownership, real autocomplete lookups
and live tracking remain
production requirements. Aggregate view counts are illustrative. The registered
Assign and Events list contributions are represented; arbitrary future plugin
contributions are not fabricated. The HTML autocomplete is a sample-data adapter,
not the Dart engine. Production must reuse the engine from
`lib/src/shell/topic_filter_controller.dart` and input from
`lib/src/shell/topic_filter_input.dart`; `topic_filter_page.dart` currently owns
that composition. This artifact does not remove the live Flutter route/sidebar
entry yet; the migration above is part of implementing the approved design.

## Review — 2026-09-17

Reviewed in the Codex in-app browser:

- Dark desktop Compact, light 390px Card, dark 390px Compact, and larger text.
- No horizontal page or row overflow in the 390px pane, including long group names.
- Combined category/subcategory/tag filtering and tag-search filtering.
- New scopes/counts and Top periods; all seven preview contexts.
- All eleven preview states and pagination retry.
- Event schedule, timezone, Escape dismissal and focus restoration.
- Assignment disclosure, unread removal, adjacent-topic fallback, and keyboard
  selection/opening.
- Recent drafts, draft resumption and local draft saving.

The revised header/footer was also reviewed at desktop and 390px widths. Confirmed
plain headings, footer creation/drafts, absence of list search/refresh/count text,
conditional feed badges, badge updates after reading, and source-list navigation.
The Preferences preview no longer contains Compact / Card; Display retains both.
The combined feed/period menu was checked at desktop and 390px widths: all six
periods are visible, the selected period is checked and named in the trigger,
category/subcategory filters survive selection, and Top adds no refinement row.

JavaScript syntax passes `node --check`. The inspected browser log contained no
warnings or errors. Touch gestures are implemented but were not tested on a
physical device. This review concerns the HTML prototype, not the Flutter app.
