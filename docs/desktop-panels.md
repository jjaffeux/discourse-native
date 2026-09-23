# Desktop document panels

Desktop forum workspaces have a main panel and a secondary panel. Each panel
selects its own tab; the workspace's active tab identifies the panel that owns
keyboard input and navigation from the sidebar. Swapping panel positions does
not change their identities or selected documents.

Normal navigation creates and selects a tab in the current panel. Topics and
chat threads default to the secondary panel. Middle-click also targets the
secondary panel. A tab can be dragged onto another tab strip or into the other
panel, including an empty panel. Moving a tab preserves its ID, route history,
and reading anchors. Close-other-tabs and adjacent-tab shortcuts operate within
the relevant panel. The existing per-forum tab limit applies across both panels.

`ForumTab.panel` and the selected tab in each panel are persisted in
`ForumWorkspace`. Snapshots without panel metadata assign topic tabs to the
secondary panel and other tabs to main. When space is insufficient for two
readable columns, both tab strips remain available and the focused panel's
content fills the workspace. Mobile keeps its existing single-surface navigation.

`DesktopPanels` owns the layout and stable widget keys. `ForumTabScope` identifies
the document being rendered. `ShellSelector`, `ForumTabLayoutBuilder`, and
`ForumTabListenableBuilder` resolve synchronous presentation reads through
`ShellController.readTab`; they never change input focus. Other deferred builders
that read route-dependent shell state must use the same scope. Do not keep a
read scope across an asynchronous operation: capture the tab ID and route, then
use the targeted controller methods or a fresh synchronous read instead.

Pointer and keyboard focus in a panel select its document before actions run.
Viewport bindings keep their owning tab ID, so scrolling or paging one reader
cannot save anchors into another. Both selected documents hydrate on restoration,
and visible topics retain their message-bus subscriptions when focus changes.

Focused coverage lives in `desktop_panels_test.dart`, `desktop_topic_page_test.dart`,
`forum_tabs_integration_test.dart`, `sidebar_active_destination_test.dart`, and the
chat navigation and site tracker suites.
