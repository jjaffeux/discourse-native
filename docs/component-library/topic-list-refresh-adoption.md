# Topic-list pull to refresh

The shared `TopicListView` already covers forum feeds, category/tag feeds,
filtered lists, private-message inboxes, and group topic feeds. Aggregate and
assigned-topic lists now use the same public Native `DPullToRefresh` component.
User activity and drafts keep one refresh owner across their loading, empty,
error, and populated states. Their empty/error content uses one always-scrollable
viewport so dragging over the message can refresh it.

Refresh state is keyed to the aggregate tab, assignment presentation/filter/query,
or activity/draft account. Draft fetching retains its existing reload behavior.

## Verification — 2026-09-16

- `flutter analyze --no-pub`: clean. Flutter 3.47.4 / Dart 3.13.3;
  repository SDK pin and lockfile unchanged.
- 137 tests passed across `aggregate_view_test.dart`,
  `assigned_group_view_test.dart`, `activity_section_lifecycle_test.dart`,
  `draft_list_test.dart`, `topic_list_view_lifecycle_test.dart`,
  `d_pull_to_refresh_test.dart`, and `group_pages_host_test.dart`.
- One additional assignment interaction passed: switching filters while a pull
  is pending allows a new refresh, and the old completion does not clear it.
- The broader message-inbox suite had 17 passes and three failures concerning
  keyboard focus and folder targets at 200% text. All three reproduced on
  unchanged `bdec7bae` in an isolated baseline worktree.
- Built and launched an isolated offline macOS fixture using production widgets.
  Inspected aggregate and activity at 390px in light mode; drafts at 390px and
  1000px in dark mode; assignments at 1000px in dark mode and 390px in light mode.
  Verified drag feedback, request completion, empty-list refresh, activity
  failure/retry, and the Native styleguide's short-list example incrementing.
- The fixture enabled mouse drags with iOS scroll physics. This was a macOS
  native review, not physical-device or iOS simulator testing. Its ad-hoc bundle
  used an alternate identifier and verified debug-only entitlements; production
  signing configuration was unchanged.
