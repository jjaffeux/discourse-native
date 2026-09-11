# Topic list inbox design

Implemented the approved `topics-inbox.html` study using the public Native kit.

- `DItem` replaces the ledger row surface. Titles retain Discourse tracking
  dots, unread counts and fully-read colors. Optional excerpts, last-poster
  identity, reply count and activity time remain separate from taxonomy.
- `DBadge.outline` supplies tags. Overflow has a tooltip listing hidden tags.
  Category navigation uses `DBreadcrumbLink`.
- Assign supplies labelled person/group metadata in the item footer, including
  a post number for indirect assignments. It retains its existing permissions,
  serializer gates and accessibility descriptions.
- Latest, Unread and New use `DTabs`. Top and Trending remain under More, with
  the existing top-period and unified-new controls retained. Narrow panes put
  feed navigation below the heading.
- `DInputGroup` searches the current list with a 300ms debounce. Category,
  multiple tags, feed and other existing query filters remain in the request.
  Enter submits immediately; Escape/Clear removes only the search. Query-specific
  feed identities isolate pagination, responses and scroll positions. Account
  and tab ownership prevents an old editor from changing a replacement session.

The server request uses Discourse's existing `search` topic-list option, which
filters post search data inside the list query:
[TopicQuery source](https://github.com/discourse/discourse/blob/main/lib/topic_query.rb).
It does not filter only loaded client rows or construct advanced search syntax.
No kit component was extended, and no dependencies or Flutter version changed.

## Verification — 2026-09-11

- Focused `flutter analyze --no-pub`: no issues in changed production sources,
  new search tests, updated navigation/list/Assign tests and native fixture.
- 198 tests passed across `content_route_test`, `topic_list_search_test`,
  `topic_list_navigation_test`, `topic_list_view_lifecycle_test`,
  `assign_plugin_test`, `aggregate_view_test`, `assigned_group_view_test`,
  `topic_inbox_test`, and `topic_tag_navigation_model_test`.
- macOS debug build succeeded. Ran `tool/topics_inbox_review_main.dart`, mounting
  the real shell, list, toolbar and Assign plugin with offline data. Inspected
  light/dark appearance, wide/390px panes, 100%/200% text, tracking states,
  assignment footer, and native accessibility ancestry. The field is separate
  from the topic links; category and tag links remain independent children.
- Native search error presentation was inspected; search scope, clearing,
  debounce and feed switching were verified with fake-server widget tests.
  Live-server search and physical iOS/Android devices were not exercised.
- Updated old column/height assertions to the approved card layout while
  retaining scrolling, pagination, reader-state and navigation regression checks.

The offline fixture can be rerun with:

```sh
flutter run -d macos --no-pub -t tool/topics_inbox_review_main.dart
```
