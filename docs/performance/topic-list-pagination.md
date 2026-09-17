# Topic-list pagination rebuilds

The September 17 compact-list debug capture recorded 133 over-budget UI frames
out of 927 at 120 Hz, with no over-budget raster frames. Of those slow frames,
128 also built rows. All 22 whole-list rebuild frames were over budget while
the feed grew from 30 to 330 topics. These debug timings identify investigation
areas; they do not measure release performance.

## Change

Mounted `_TopicRow` instances retain their selector subtree when a parent list
rebuilds with unchanged row configuration. Pagination can update the loading
footer and append topic IDs without rebuilding existing row contents. Retention
is scoped to the mounted row, so discarded sliver rows do not accumulate in a
feed-wide widget cache. Topic refs, category selectors, inbox selection and
inherited theme/plugin dependencies continue to update their own consumers.
Changing row configuration (including display mode) replaces the cached subtree.

The scroll capture now distinguishes delegate invocations (`topicList.row.built`)
from synchronous row subtree construction (`topicList.row.build`) and row layout
(`topicList.row.layout`). The new events contain topic IDs and microsecond
durations, not titles. Build measurements surround the row body's element
rebuild, including synchronous descendant work; they do not include independently
scheduled descendant rebuilds. Layout timings surround its render subtree.
Neither timer allocates events or starts a stopwatch while recording is off.
Report summaries include distributions and per-frame measured totals.

The local profile fixture supports `--dart-define=LIST_PAGE_SIZE=30`, delays each
local page by 50 ms, and listens to feed changes. Omit this define to retain the
existing preloaded-list benchmark.

## Verification

- On baseline `baaed04b`, entering pagination's loading state rebuilt 8 existing
  card titles and 12 compact titles in the regression fixture. With retention,
  both loading and append rebuild zero existing titles; updating a topic still
  rebuilds its one title, and switching display modes updates the row.
- The rebuild observer now tracks element identity. Flutter's `builtOnce` debug
  hook argument was always false unless rebuild logging was enabled, so the
  previous assertion could miss rebuilds.
- All 82 focused tests passed, covering paging, card/compact mode, live updates, scrolling
  with event/assignment plugins, read-removal, semantics and capture exports.
- Formatting, `git diff --check`, and root `flutter analyze --no-pub` passed.
- The broader run's pre-existing `feed select retains keyboard focus across
  routes (stacked: true)` failure (`topWeekly` instead of `popular`) reproduces
  with the original `topic_list_view.dart` as well. The same failure was already
  recorded in `compact-topic-list-scrolling.md`.
- Native profile builds were attempted for both the changed and original row
  implementation. Both failed in Flutter's AOT snapshotter with `Class with
  illegal cid, full-aot` for `_window_macos.dart`'s `_Rect`. The installed SDK is
  Flutter 3.47.4 / Dart 3.13.3; no SDK or dependency pins were changed. No new
  native frame-time or visual-verification claim is made for this change.
