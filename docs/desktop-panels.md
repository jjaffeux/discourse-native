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
At the limit, topic-row clicks show “Close a tab before opening another.” and
preserve all existing documents. Closing a tab allows the next click to open.

Dragging between panels shows a Native document-tab placeholder at the insertion
position. Hovering over the panel content previews an appended tab; an empty panel
previews its first tab. The floating drag preview sits below the pointer so the
placeholder stays visible. Insertion boundaries retain the tabs' rendered widths
before the placeholder appeared, including across nested drag targets, so the
preview does not jump as tabs shift. Leaving or cancelling the drag clears it
without changing the workspace.

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

Verification on 2026-09-23: 544 tests passed across 24 focused suites, including
mobile navigation, independent reader lifecycles, filter ownership, rebuild
isolation, session restoration, chat threads, tab movement, and persistence.
`flutter analyze --no-pub` reported no issues and the macOS debug build succeeded.
Native inspection covered topic navigation, ordinary navigation in the focused
panel, middle-click, dragging between panels, swapping positions, closing an
unfocused panel's tab, and the narrow layout in dark mode. The final build also
confirmed that opening Categories beside a topic list preserves the list's
heading and creation action.

The passing run excluded 15 failures reproduced in the pre-refactor baselines:
four tab appearance tests, two mobile tab-subtree expectations, one composer
docking test, seven existing chat tests, and one compact creation-button height
expectation. Those baseline failures were not changed as part of this refactor.

The drag-placeholder follow-up passed 78 focused tests across desktop panels,
tab controls, tab integration and rebuild isolation. This run excluded the six
tab appearance/mobile subtree baseline failures listed above. It covers empty
and occupied destinations, insertion before/between/after tabs in both text
directions, movement between the strip and panel content, cancellation and the
narrow desktop layout. Static analysis reported no issues. Offscreen Flutter
renders at 1200×850 with macOS SFNS fonts verified the light/dark placeholder and
floating preview. Native macOS fixture checks exercised insertion before and
after an existing tab, moving back into an empty panel, and moving between the stacked
tab strips in dark mode. The in-progress placeholder was inspected in the
offscreen renders; native automation releases the pointer at the end of a drag.
