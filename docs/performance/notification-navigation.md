# Notification navigation viewport trace

The regression fixture in `test/notification_list_test.dart` clicks a real
notification row while a 180-post topic is open. Posts have varied heights,
including long HTML bodies. It holds the refresh response for four simulated
16 ms frames and records the visible post and scroll offset on every frame.

Run the assertions with the scroll instrumentation printed:

```sh
flutter test test/notification_list_test.dart \
  --plain-name 'notification refresh preserves' \
  --dart-define=TRACE_NOTIFICATION_SCROLL=true --reporter expanded
```

The original sequence when post 137 was already visible was:

1. Notification navigation advanced the navigation revision.
2. The viewport retired its scroll and list controllers. The replacement
   controller started at zero, and the post widgets were mounted again.
3. Initial restoration waited for the topic refresh. Post 137 disappeared
   throughout that wait, even though it was already loaded.
4. When the response arrived, restoration jumped using estimated heights.
   A subsequent layout measured the destination, and the second scheduled
   jump settled at the same target.

For this fixture, the frame observations were:

| Frame | Before the fix | After the fix |
| --- | --- | --- |
| Before click | Post 137, scroll offset 27331 | Post 137, scroll offset 27331 |
| 0–3, refresh pending | Opening posts, scroll offset 0 | Post 137, scroll offset 27331 |
| 4, response released | Estimated jump to 27425; target not yet laid out | Post 137, scroll offset 27331 |
| 5–19 | Post 137, scroll offset 27331 | Post 137, scroll offset 27331 |

Navigation now retains the controllers, measured post heights, mounted post
bodies, and header within the same topic, tab, shell, and account session.
Queued work still belongs to a navigation generation and is invalidated when
a new destination supersedes it. Account changes and topic/tab switches retire
the old viewport. An explicit jump to post 1 still moves to the start.

The tests cover clicking from the target itself and from another post, as well
as rejecting stale queued work across navigation and account changes. The
existing topic scroll capture's `topic.controllers.sync` event now includes
`viewportRetained`, `targetPostNumber`, and `loading` to expose this sequence in
live diagnostic captures without enabling routine logging.
