# Topic-list cursor ownership

TopicListCursorCoordinator owns keyboard cursor changes, source-row hints,
sparse selection recovery, paging for keyboard movement, and selected-topic
restoration. A coordinator captures one ShellTabContext and destination for
its lifetime. Every asynchronous continuation checks that captured tab,
account lease, destination, route, and operation token before it commits a
cursor or invokes a UI effect.

TopicListView constructs a coordinator when its existing feed identity changes.
It passes the saved PageStorage cursor and renders the coordinator's read-only
cursor listenable. Cursor writes precede focus, prefetch, or navigation. Opening
a row cancels both pending keyboard operations before remembering that topic.
Hiding the list cancels selected-topic restoration without erasing the cursor.
The coordinator retires immediately when its list or shell is replaced. Its
notifier is disposed after the outgoing scrollable detaches.

The widget supplies shortcut availability, focus and prefetch effects, row
reveal, navigation, PageStorage writes, and post-frame registration. The
coordinator schedules guarded movement reveal before matching-token retirement.
Even an unsuccessful movement holds admission until the next frame. The widget
never interprets a keyboard transaction token or resumes a partial transaction.
The coordinator can run with a manually drained frame queue and no Flutter
binding.

Initial scroll restoration and its loaded-page clamp remain in TopicListView.
The widget also keeps pixel-anchor correction, boundary jumps, external inbox
reading reveals, feed retention, viewport publication, and visible-gap range
scheduling. TopicFeedController owns sparse resident pages and network request
capabilities. Predictive prefetch and Topic and Chat reader policies retain
their existing owners. This extraction does not hydrate unloaded pages to reach
a saved initial row.

Two independent designs compared this bounded transaction with a full viewport
owner and a source/effects interface. Independent comparison selected the
captured tab facade and complete cursor operations. The wider alternatives
added staged acceptance and duplicated currentness rules at the widget edge.
The chosen shape removes the widget's cursor reconciliation and both keyboard
request tokens without changing geometry or retention policy.

The headless coordinator suite pins admission, source-tab ownership and retired
work. The selection lifecycle, topic-list lifecycle, read-removal, hover
prefetch, feed-controller and scroll construction suites cover the UI adapter.
Rendered replays compare saved-row, keyboard and reordered-feed states at
narrow and desktop widths. This structural change makes no runtime speed claim.
